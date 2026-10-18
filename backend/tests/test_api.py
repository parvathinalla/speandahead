"""API tests use an in-memory Nessie fake; no API keys or real transfers."""
from datetime import date, timedelta
import json

import pytest
from fastapi.testclient import TestClient

import main


class FakeNessie:
    def __init__(self):
        self.data = {
            "checking": 500, "savings": 1200,
            "card_a": 750, "card_b": 200,
            "joint_demo": 2000, "partner_checking": 350,
        }

    async def account(self, account_id):
        if account_id not in self.data:
            raise AssertionError("Wrong account ID")
        return {"_id": account_id, "balance": self.data[account_id],
                "type": "Credit Card" if account_id.startswith("card") else "Checking",
                "nickname": "Demo " + account_id}


@pytest.fixture
def client(tmp_path, monkeypatch):
    today = date.today()
    m = {
        "ids": {"accounts": {k: k for k in FakeNessie().data}},
        "app_bills": {
            name: {
                "status": "pending", "payment_amount": amt,
                "payment_date": (today + timedelta(days=day)).isoformat(),
                "upcoming_payment_date": (today + timedelta(days=day)).isoformat(),
                "payee": name, "account_id": "checking",
                "nickname": name, "source": "app_simulation",
            }
            for name, amt, day in [("rent", 400, 3), ("electricity", 150, 7), ("internet", 100, 12)]
        },
        "app_scenario": {
            "card_a": {"limit_usd": 1000, "rewards": {"groceries": .03},
                       "statement_closes_in_days": 9},
            "card_b": {"limit_usd": 2000, "rewards": {"groceries": .02},
                       "statement_closes_in_days": 13},
        },
    }
    manifest_path = tmp_path / "seed_manifest.json"
    manifest_path.write_text(json.dumps(m))
    monkeypatch.setattr(main, "MANIFEST", manifest_path)
    monkeypatch.setattr(main, "SQLITE", tmp_path / "actions.sqlite3")
    monkeypatch.setattr(main, "AUTH_MODE", "demo")
    monkeypatch.setattr(main, "DATA_MODE", "nessie")
    monkeypatch.setattr(main, "DEMO_STORE", "sqlite")
    monkeypatch.setattr(main, "PAYMENT_MODE", "simulate")
    main.app.state.nessie = FakeNessie()
    with TestClient(main.app) as test_client:
        yield test_client
    del main.app.state.nessie


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["status"] == "ok"


def test_dashboard_reads_seeded_nessie_accounts(client):
    response = client.get("/api/dashboard")
    assert response.status_code == 200, response.text
    data = response.json()
    assert len(data["accounts"]) == 6
    assert data["bill_forecast"]["total_bills_due"] == 650
    assert data["bill_forecast"]["shortfall_amount"] == 150
    assert data["bill_forecast"]["data_sources"]["bills"] == "local_app_simulation"


def test_bill_forecast(client):
    response = client.post("/api/bills/forecast", json={"horizon_days": 4})
    assert response.status_code == 200
    assert response.json()["total_bills_due"] == 400


def test_card_recommendation(client):
    response = client.post("/api/cards/evaluate",
                           json={"purchase_amount": 120, "purchase_category": "groceries"})
    assert response.status_code == 200, response.text
    assert response.json()["recommended_card"]["card_name"] == "card_b"


def test_autopay_guards_against_exhausting_bill_money(client):
    response = client.post("/api/autopay/preview", json={"target_utilization_pct": 29})
    assert response.status_code == 200
    data = response.json()
    assert data["suggested_paydown_amount"] == 460
    assert data["recommended_payment_amount"] == 0
    assert data["auto_execution"] is False


def test_autopay_plan_refuses_infeasible_payment(client):
    response = client.post("/api/autopay/plans",
                           json={"target_utilization_pct": 29, "confirmed": True})
    assert response.status_code == 409


def test_emergency_gap(client):
    response = client.post("/api/emergency/evaluate",
                           json={"emergency_cost": 1000, "safety_buffer": 300})
    assert response.status_code == 200
    assert response.json()["potential_gap"] == 250


def test_legacy_joint_partner_routes_are_unavailable(client):
    assert client.post('/api/joint/proposals', json={'confirmed': True}).status_code == 404


def test_transfer_requires_confirmation_and_is_idempotent(client):
    payload = {"amount": 100, "idempotency_key": "test-unique-0001"}
    denied = client.post("/api/transfers/execute", json=payload)
    assert denied.status_code == 400
    granted = client.post("/api/transfers/execute",
                          json={**payload, "confirmed": True})
    assert granted.status_code == 200, granted.text
    assert granted.json()["status"] == "simulated_only"
    repeated = client.post("/api/transfers/execute",
                           json={**payload, "confirmed": True})
    assert repeated.status_code == 200
    assert repeated.json()["previous_request"] is True
    mismatch = client.post("/api/transfers/execute",
                           json={**payload, "amount": 101, "confirmed": True})
    assert mismatch.status_code == 409


def test_integrated_purchase_decision(client):
    r = client.post("/api/decisions/purchase",
                    json={"purchase_amount": 120, "purchase_category": "groceries",
                          "emergency_cost": 1000})
    assert r.status_code == 200, r.text
    assert r.json()["recommended_card"]["card_name"] == "card_b"
    assert r.json()["emergency_stress_test"]["potential_gap"] == 250


def test_auth0_mode_rejects_missing_token(client, monkeypatch):
    monkeypatch.setattr(main, "AUTH_MODE", "auth0")
    assert client.get("/api/dashboard").status_code == 401

def test_nessie_snapshot_coalesces_simultaneous_account_reads():
    """Five UI tabs should never trigger thirty Nessie account requests."""
    import asyncio

    class CountingGateway(main.NessieGateway):
        def __init__(self):
            super().__init__()
            self.calls = 0

        async def account(self, account_id):
            self.calls += 1
            await asyncio.sleep(.005)
            return {"_id": account_id, "balance": 100}

    async def fetch():
        gateway = CountingGateway()
        ids = {name: name for name in (
            "checking", "savings", "card_a", "card_b",
            "joint_demo", "partner_checking")}
        responses = await asyncio.gather(*(
            gateway.account_snapshot(ids) for _ in range(5)))
        assert len(responses) == 5
        assert all(len(r) == 6 for r in responses)
        assert gateway.calls == 6
        # Reusing the snapshot should not query Nessie again.
        await gateway.account_snapshot(ids)
        assert gateway.calls == 6
        # An explicit invalidation must trigger six new reads.
        gateway._cache_until = 0
        await gateway.account_snapshot(ids)
        assert gateway.calls == 12

    asyncio.run(fetch())


def test_nessie_gateway_retries_only_safe_get(monkeypatch):
    """Transient GET errors are retried; potentially mutating POST is not."""
    import asyncio
    import httpx
    from fastapi import HTTPException

    monkeypatch.setenv("NESSIE_API_KEY", "unit-test-not-a-real-key")
    original_client = httpx.AsyncClient
    calls = []

    def handler(request):
        calls.append(request.method)
        if request.method == "GET" and calls.count("GET") < 3:
            return httpx.Response(503, json={"error": "temporary"})
        if request.method == "POST":
            return httpx.Response(503, json={"error": "temporary"})
        return httpx.Response(200, json={"_id": "fake-id", "balance": 500})

    def mock_client(**kwargs):
        return original_client(transport=httpx.MockTransport(handler), **kwargs)

    monkeypatch.setattr(main.httpx, "AsyncClient", mock_client)

    async def verify():
        gateway = main.NessieGateway()
        account = await gateway.request("GET", "/accounts/fake-id")
        assert account["_id"] == "fake-id"
        assert calls.count("GET") == 3
        try:
            await gateway.request("POST", "/accounts/fake-id/transfers",
                                  {"amount": 10})
        except HTTPException as exc:
            assert exc.status_code == 503
        else:
            raise AssertionError("POST should fail, never silently succeed")
        assert calls.count("POST") == 1

    asyncio.run(verify())


def test_auth0_multiuser_isolation_with_real_rs256_tokens(client, monkeypatch, tmp_path):
    """JWTs must have valid RS256 signature, issuer, audience, expiry and subject.
    Newly registered users cannot inherit Sarah's original Nessie mapping.
    """
    import hashlib
    from datetime import datetime, timezone
    from types import SimpleNamespace
    from cryptography.hazmat.primitives.asymmetric import rsa
    from scripts.link_user_sandbox import provision
    import jwt

    priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pub = priv.public_key()

    class StaticKeys:
        def __init__(self, *args, **kwargs):
            pass

        def get_signing_key_from_jwt(self, token):
            return SimpleNamespace(key=pub)

    monkeypatch.setattr(main.jwt, "PyJWKClient", StaticKeys)
    monkeypatch.setattr(main, "AUTH_MODE", "auth0")
    monkeypatch.setattr(main, "TENANTS_DIR", tmp_path / "isolated_users")
    monkeypatch.setenv("AUTH0_DOMAIN", "fictional-tenant.us.auth0.com")
    monkeypatch.setenv("AUTH0_AUDIENCE", "https://api.creditpilot.test")

    def token(sub, **overrides):
        claims = {
            "sub": sub,
            "iss": "https://fictional-tenant.us.auth0.com/",
            "aud": "https://api.creditpilot.test",
            "iat": int(datetime.now(timezone.utc).timestamp()),
            "exp": int(datetime.now(timezone.utc).timestamp()) + 300,
        }
        claims.update(overrides)
        return jwt.encode(claims, priv, algorithm="RS256", headers={"kid": "test"})

    def headers(sub, **overrides):
        return {"Authorization": "Bearer " + token(sub, **overrides)}

    owner = "auth0|alice123"
    guest = "auth0|bob123"
    partner = "auth0|partner123"
    # A real signup token is accepted but sees an empty onboarding state.
    new_user = client.get("/api/me", headers=headers(guest))
    assert new_user.status_code == 200, new_user.text
    assert new_user.json()["sandbox_linked"] is False
    assert new_user.json()["security_mode"] == "auth0"
    assert client.get("/api/dashboard", headers=headers(guest)).status_code == 409

    # Local admin explicitly assigns the seed to Alice.
    provision(main.MANIFEST, main.TENANTS_DIR, owner, partner)
    owner_status = client.get("/api/me", headers=headers(owner))
    assert owner_status.status_code == 200
    assert owner_status.json()["sandbox_linked"] is True
    assert client.get("/api/dashboard", headers=headers(owner)).status_code == 200

    # Bob cannot read Alice's account or perform actions using that mapping.
    for endpoint in ("/api/dashboard", "/api/accounts", "/api/bills"):
        assert client.get(endpoint, headers=headers(guest)).status_code == 409

    invalid = [
        headers(owner, aud="https://another-app.invalid"),
        headers(owner, iss="https://evil.us.auth0.com/"),
        headers(owner, exp=1),
    ]
    for bad in invalid:
        assert client.get("/api/me", headers=bad).status_code == 401

    # Even a correctly signed JWT from a wrong key is rejected.
    attacker_private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    forged = jwt.encode({
        "sub": owner, "iss": "https://fictional-tenant.us.auth0.com/",
        "aud": "https://api.creditpilot.test",
        "exp": int(datetime.now(timezone.utc).timestamp()) + 300,
    }, attacker_private, algorithm="RS256", headers={"kid": "fake"})
    assert client.get("/api/me",
                      headers={"Authorization": "Bearer " + forged}).status_code == 401

    # An individual sandbox mapping never grants joint membership.
    assert client.get('/api/joint/membership', headers=headers(owner)).json() == {'has_joint_account': False}
    assert client.get('/api/joint/payments', headers=headers(guest)).status_code == 403


def test_provisioning_does_not_share_nessie_accounts_between_auth0_users(tmp_path):
    from scripts.link_user_sandbox import provision
    from pathlib import Path
    import json

    directory = tmp_path / "tenants"
    source1 = tmp_path / "seed1.json"
    source2 = tmp_path / "seed2.json"
    payload = {
        "ids": {"accounts": {str(i): "account-" + str(i) for i in range(6)}},
        "app_bills": {"rent": {"payment_amount": 100}},
    }
    source1.write_text(json.dumps(payload))
    source2.write_text(json.dumps(payload))
    result = provision(source1, directory, "auth0|first")
    assert result.is_file()
    assert json.loads(result.read_text())["owner_sub"] == "auth0|first"
    with pytest.raises(ValueError, match="never be shared"):
        provision(source2, directory, "auth0|second")
    with pytest.raises(ValueError, match="already bound"):
        provision(source1, directory, "auth0|first")


def test_auth_token_errors_explain_only_safe_reason_in_dev(monkeypatch):
    from fastapi import HTTPException
    monkeypatch.setattr(main, "ENVIRONMENT", "development")
    issue = main.auth_error("audience_mismatch")
    assert isinstance(issue, HTTPException)
    assert issue.status_code == 401
    assert issue.detail == "Invalid authentication token (audience_mismatch)"
    monkeypatch.setattr(main, "ENVIRONMENT", "production")
    prod = main.auth_error("audience_mismatch")
    assert prod.status_code == 401
    assert prod.detail == "Invalid or expired authentication token"
    assert "audience" not in prod.detail
