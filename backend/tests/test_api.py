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


def test_joint_requires_distinct_partner_approval(client):
    proposal = client.post("/api/joint/proposals",
                           json={"amount": 850, "confirmed": True})
    assert proposal.status_code == 200, proposal.text
    proposal_id = proposal.json()["proposal_id"]
    own = client.post("/api/joint/proposals/" + proposal_id + "/decision",
                      json={"approve": True})
    assert own.status_code == 403
    partner = client.post("/api/joint/proposals/" + proposal_id + "/decision",
                          headers={"X-Demo-User": "jamie"}, json={"approve": True})
    assert partner.status_code == 200
    assert partner.json()["status"] == "approved_simulation"


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
