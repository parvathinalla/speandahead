"""Opt-in chat memory tests; multiple Auth0 users must remain isolated."""
import json
from types import SimpleNamespace
from datetime import datetime, timezone
from uuid import uuid4

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
import pytest

import main
from agent_memory import AgentMemory
from agent_service import snapshot


def test_private_memory_is_opt_in_and_deletable(tmp_path):
    m = AgentMemory(tmp_path / "agent.sqlite3")
    m.init()
    assert not m.enabled("auth0|alice")
    assert not m.append("auth0|alice", "user", "Please remember I prefer cash back.")
    assert m.history("auth0|alice") == []
    with pytest.raises(ValueError):
        m.remember("auth0|alice", str(uuid4()), "Cash back over travel")
    m.set_enabled("auth0|alice", True)
    item = m.remember("auth0|alice", str(uuid4()), "Cash back over travel")
    m.append("auth0|alice", "user", "Should I use my cash-back card?")
    m.append("auth0|alice", "assistant", "Compare spending category rewards.")
    assert len(m.memories("auth0|alice")) == 1
    assert len(m.history("auth0|alice")) == 2
    assert m.memories("auth0|bob") == []
    assert m.history("auth0|bob") == []
    assert not m.remove("auth0|bob", item["id"])
    assert len(m.memories("auth0|alice")) == 1
    m.set_enabled("auth0|alice", False)
    assert m.memories("auth0|alice") == []
    assert m.history("auth0|alice") == []
    m.set_enabled("auth0|alice", True)
    assert m.memories("auth0|alice") == []
    assert m.history("auth0|alice") == []


def test_snapshot_has_no_account_ids_or_account_nicknames():
    value = snapshot({
        "checking": {"_id": "NESSIE-SECRET-ID", "nickname": "John Doe",
                     "type": "Checking", "balance": 1600},
        "savings": {"_id": "SECRET-SAVINGS-ID", "nickname": "Private Savings",
                    "type": "Savings", "balance": 900},
    }, {"source": "nessie_sandbox"},
        {"checking_balance": 1600, "savings_balance": 900,
         "total_bills_due": 130}, {})
    encoded = json.dumps(value)
    assert "NESSIE-SECRET-ID" not in encoded
    assert "John Doe" not in encoded
    assert "SECRET-SAVINGS-ID" not in encoded
    assert value["source"] == "nessie_sandbox"
    assert value["cashflow_14days"]["checking_balance_usd"] == 1600


@pytest.fixture
def secure_agent_client(monkeypatch, tmp_path):
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public = private.public_key()
    monkeypatch.setattr(main, "AUTH_MODE", "auth0")
    monkeypatch.setattr(main, "DATA_MODE", "synthetic")
    monkeypatch.setattr(main, "DEMO_STORE", "sqlite")
    monkeypatch.setattr(main, "SQLITE", tmp_path / "bank.sqlite3")
    monkeypatch.setenv("AUTH0_DOMAIN", "sample.us.auth0.com")
    monkeypatch.setenv("AUTH0_AUDIENCE", "https://api.creditpilot.test")
    monkeypatch.setattr(main, "auth0_jwks", lambda _: SimpleNamespace(
        get_signing_key_from_jwt=lambda _: SimpleNamespace(key=public)))
    memory = AgentMemory(tmp_path / "memory.sqlite3")
    memory.init()
    monkeypatch.setattr(main, "agent_memory", lambda: memory)
    now = int(datetime.now(timezone.utc).timestamp())
    def headers(subject):
        token = jwt.encode({
            "sub": subject, "iss": "https://sample.us.auth0.com/",
            "aud": "https://api.creditpilot.test", "iat": now, "exp": now + 500,
        }, private, algorithm="RS256")
        return {"Authorization": "Bearer " + token}
    with TestClient(main.app) as client:
        yield client, headers


def test_ai_chat_uses_verified_banking_context_and_private_notes(
        secure_agent_client, monkeypatch):
    client, headers = secure_agent_client
    seen = []
    async def fake_gemini(message, banking, notes, history):
        seen.append((message, banking, notes, history))
        return "A plan grounded in your own demo balances.", True
    monkeypatch.setattr(main, "ask_gemini", fake_gemini)
    alice, bob = headers("auth0|alice"), headers("auth0|bob")
    assert client.get("/api/agent/settings", headers=alice).json()["memory_enabled"] is False
    assert client.post("/api/agent/chat", headers=alice,
        json={"message": "Can I buy a laptop?"}).status_code == 200
    assert seen[-1][2] == []
    assert client.get("/api/agent/history", headers=alice).json()["history"] == []
    client.post("/api/agent/settings", headers=alice, json={"enabled": True})
    saved = client.post("/api/agent/memories", headers=alice,
        json={"note": "I prefer cash back, avoid travel rewards."})
    assert saved.status_code == 200
    memory_id = saved.json()["memory"]["id"]
    second = client.post("/api/agent/chat", headers=alice,
        json={"message": "Which credit card should I use?"})
    assert second.status_code == 200
    assert len(seen[-1][2]) == 1
    assert len(client.get("/api/agent/history", headers=alice).json()["history"]) == 2
    assert client.get("/api/agent/memories", headers=bob).json()["memories"] == []
    assert client.post(f"/api/agent/memories/{memory_id}/delete",
        headers=bob).status_code == 404
    assert client.post(f"/api/agent/memories/{memory_id}/delete",
        headers=alice).status_code == 200
    assert client.post("/api/agent/settings", headers=alice,
        json={"enabled": False}).status_code == 200
    assert client.get("/api/agent/history", headers=alice).json()["history"] == []
