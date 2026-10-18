"""Live API shape tests with a cryptographically signed Auth0-like JWT.

All banking records are synthetic and persisted in a temporary SQLite file;
the HTTP API must not call Nessie when DEMO_DATA_MODE=synthetic.
"""
from datetime import date, datetime, timedelta, timezone
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

import main
import synthetic_bank


@pytest.fixture
def web_client(tmp_path, monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_key = key.public_key()
    monkeypatch.setattr(main, "SQLITE", tmp_path / "creditpilot.sqlite3")
    monkeypatch.setattr(main, "AUTH_MODE", "auth0")
    monkeypatch.setattr(main, "DATA_MODE", "synthetic")
    monkeypatch.setenv("AUTH0_DOMAIN", "fictional-tenant.us.auth0.com")
    monkeypatch.setenv("AUTH0_AUDIENCE", "https://api.creditpilot.test")
    monkeypatch.setattr(
        main, "auth0_jwks",
        lambda domain: SimpleNamespace(
            get_signing_key_from_jwt=lambda token: SimpleNamespace(key=public_key)))
    now = int(datetime.now(timezone.utc).timestamp())

    def headers(subject):
        token = jwt.encode({
            "sub": subject,
            "aud": "https://api.creditpilot.test",
            "iss": "https://fictional-tenant.us.auth0.com/",
            "iat": now, "exp": now + 600,
        }, key, algorithm="RS256")
        return {"Authorization": "Bearer " + token}

    with TestClient(main.app) as client:
        yield client, headers


def test_signup_assigns_one_of_500_unique_profiles(web_client):
    client, auth = web_client
    assert client.get("/api/me").status_code == 401
    a = client.get("/api/me", headers=auth("auth0|alice"))
    b = client.get("/api/me", headers=auth("auth0|bob"))
    again = client.get("/api/me", headers=auth("auth0|alice"))
    assert a.status_code == b.status_code == 200
    assert a.json()["sandbox_linked"]
    assert a.json()["data_source"] == "synthetic_banking_demo"
    assert a.json()["portfolio_id"] == again.json()["portfolio_id"]
    assert a.json()["portfolio_id"] != b.json()["portfolio_id"]
    catalog = client.get("/api/demo/catalog", headers=auth("auth0|alice")).json()
    assert catalog == {
        "profiles_total": 500,
        "profiles_claimed": 2,
        "profiles_available": 498,
        "source": "synthetic_banking_demo",
    }


def test_complete_dynamic_financial_api_for_new_user(web_client):
    client, auth = web_client
    head = auth("google-oauth2|member_12345")
    assert client.get("/api/me", headers=head).status_code == 200

    accounts = client.get("/api/accounts", headers=head).json()["accounts"]
    assert len(accounts) >= 10
    assert all(item["source"] == "synthetic_banking_demo" for item in accounts)
    card_list = client.get("/api/cards/catalog", headers=head).json()["cards"]
    assert 6 <= len(card_list) <= 8
    assert any(c["display_name"] == "Horizon Flight Reserve" for c in card_list)
    assert all(c["visual_theme"] for c in card_list)
    assert all(c["display_name"] not in ("Card A", "Card B") for c in card_list)
    assert all(len(c["last4"]) == 4 for c in card_list)

    tx = client.get("/api/transactions?limit=10", headers=head).json()
    assert tx["total"] >= 93
    assert len(tx["transactions"]) == 10

    bills = client.get("/api/bills", headers=head).json()
    assert 12 <= len(bills["bills"]) <= 25
    forecast = client.post("/api/bills/forecast",
                           headers=head, json={"horizon_days": 90})
    assert forecast.status_code == 200, forecast.text
    assert forecast.json()["data_sources"]["balances"] == "synthetic_banking_demo"
    assert forecast.json()["total_bills_due"] > 0

    suggestion = client.post("/api/cards/evaluate", headers=head, json={
        "purchase_amount": 120, "purchase_category": "groceries",
        "merchant_name": "Fresh Fields Market"})
    assert suggestion.status_code == 200
    assert suggestion.json()["cards"][0]["display_name"]

    paydown = client.post("/api/autopay/preview", headers=head, json={
        "account": card_list[0]["account"], "target_utilization_pct": 29})
    assert paydown.status_code == 200, paydown.text
    assert paydown.json()["card_display_name"] == card_list[0]["display_name"]

    portfolio = client.post("/api/autopay/portfolio-preview", headers=head, json={
        "include_available_savings": True, "savings_reserve": 1000,
    })
    assert portfolio.status_code == 200, portfolio.text
    optimized = portfolio.json()
    assert len(optimized["cards"]) == len(card_list)
    assert optimized["allocated_payment_total"] <= optimized["available_payment_budget"]
    assert optimized["aggregate_utilization_after_pct"] <= optimized["aggregate_utilization_before_pct"]
    assert len(optimized["notification_plan"]) == len(card_list)
    activation = client.post("/api/autopay/portfolio-plans", headers=head, json={
        "include_available_savings": False, "confirmed": True,
    })
    assert activation.status_code == 200, activation.text
    assert activation.json()["status"] == "statement_guard_active"
    assert activation.json()["execution"] == "NO BANK PAYMENT WILL OCCUR"
    assert activation.json()["cards_monitored"] == len(card_list)

    emergency = client.post("/api/emergency/evaluate", headers=head,
                            json={"emergency_cost": 1800})
    assert emergency.status_code == 200

    profile = client.get("/api/profile", headers=head).json()
    assert profile["account_count"] >= 6
    assert profile["bill_count"] >= 12
    assert profile["monthly_income"] > 0


def test_editable_bills_are_isolated_from_other_signed_in_users(web_client):
    client, auth = web_client
    alice, bob = auth("auth0|alice"), auth("auth0|bob")
    assert client.get("/api/me", headers=alice).status_code == 200
    assert client.get("/api/me", headers=bob).status_code == 200
    before = len(client.get("/api/bills", headers=alice).json()["bills"])
    due = (date.today() + timedelta(days=4)).isoformat()
    created = client.post("/api/bills/create", headers=alice, json={
        "payee": "Custom Insurance", "payment_amount": 66.33,
        "payment_date": due, "category": "insurance",
        "frequency": "monthly"})
    assert created.status_code == 200, created.text
    bill = created.json()["bill"]
    assert len(client.get("/api/bills", headers=alice).json()["bills"]) == before + 1
    assert client.post("/api/bills/" + bill["bill_id"] + "/delete",
                       headers=bob).status_code == 404
    changed = client.post("/api/bills/" + bill["bill_id"] + "/update",
                          headers=alice, json={
        "payee": "Insurance Updated", "payment_amount": 77.11,
        "payment_date": due, "category": "insurance",
        "frequency": "monthly"})
    assert changed.status_code == 200
    assert changed.json()["bill"]["payment_amount"] == 77.11
    assert client.post("/api/bills/" + bill["bill_id"] + "/delete",
                       headers=alice).status_code == 200
    assert len(client.get("/api/bills", headers=alice).json()["bills"]) == before


def test_demo_transfers_change_only_owners_simulated_balances(web_client):
    client, auth = web_client
    alice, bob = auth("auth0|alice"), auth("auth0|bob")
    client.get("/api/me", headers=alice)
    client.get("/api/me", headers=bob)
    a1 = client.get("/api/dashboard", headers=alice).json()
    b1 = client.get("/api/dashboard", headers=bob).json()
    indexed = {a["kind"]: a["balance"] for a in a1["accounts"]}
    payload = {"amount": 50, "confirmed": True, "savings_reserve": 0,
               "idempotency_key": "unique-alice-transfer-001"}
    executed = client.post("/api/transfers/execute", headers=alice, json=payload)
    assert executed.status_code == 200, executed.text
    assert executed.json()["status"] == "simulated_posted"
    same = client.post("/api/transfers/execute", headers=alice, json=payload)
    assert same.status_code == 200 and same.json()["previous_request"]
    a2 = client.get("/api/dashboard", headers=alice).json()
    after = {a["kind"]: a["balance"] for a in a2["accounts"]}
    assert after["checking"] == round(indexed["checking"] + 50, 2)
    assert after["savings"] == round(indexed["savings"] - 50, 2)
    assert client.get("/api/dashboard", headers=bob).json() == b1
    assert client.post("/api/transfers/execute", headers=bob,
                       json=payload).status_code == 409
