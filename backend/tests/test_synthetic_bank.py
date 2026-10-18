"""Financial realism, uniqueness, edits, idempotency and concurrency at 500 users."""
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
import json
import sqlite3

import pytest
import synthetic_bank as bank


def connection(path):
    result = sqlite3.connect(path, timeout=15)
    result.execute("""CREATE TABLE IF NOT EXISTS actions(
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, action_type TEXT NOT NULL,
        status TEXT NOT NULL, payload TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP)""")
    result.commit()
    return result


def test_catalog_has_500_diverse_complete_profiles(tmp_path):
    conn = connection(tmp_path / "catalog.sqlite3")
    bank.initialize(conn, count=500, as_of=date(2026, 10, 17))
    stats = bank.stats(conn)
    assert stats["profiles_total"] == 500
    assert stats["profiles_available"] == 500
    rows = conn.execute("SELECT payload FROM synthetic_profiles").fetchall()
    assert len(rows) == 500
    identities = []
    descriptions, personas, transactions = set(), set(), 0
    for (raw,) in rows:
        profile = json.loads(raw)
        personas.add(profile["persona"])
        assert len(profile["accounts"]) in (6, 7, 8)
        assert len(profile["app_scenario"]) in (2, 3, 4)
        assert 12 <= len(profile["app_bills"]) <= 25
        assert len(profile["transactions"]) >= 93
        assert "password" not in raw.lower()
        assert "email" not in raw.lower()
        assert "ssn" not in raw.lower()
        names = {card["display_name"] for card in profile["app_scenario"].values()}
        assert len(names) >= 2
        assert all(name not in ("Card A", "Card B") for name in names)
        identities.extend(profile["ids"]["accounts"].values())
        descriptions.add(tuple(sorted(names)))
        transactions += len(profile["transactions"])
    assert len(identities) == len(set(identities))
    assert len(descriptions) >= 20
    assert len(personas) == 5
    assert transactions > 45_000
    conn.close()


def test_atomic_assignment_never_reuses_a_profile(tmp_path):
    database = tmp_path / "catalog.sqlite3"
    conn = connection(database)
    bank.initialize(conn, count=500)
    conn.close()

    def claim(i):
        local = connection(database)
        try:
            return bank.get_or_claim(local, f"auth0|customer-{i}")["portfolio_id"]
        finally:
            local.close()

    with ThreadPoolExecutor(max_workers=16) as executor:
        allocated = list(executor.map(claim, range(500)))
    assert len(allocated) == len(set(allocated)) == 500

    conn = connection(database)
    assert bank.stats(conn)["profiles_available"] == 0
    assert bank.get_or_claim(conn, "auth0|customer-37")["portfolio_id"] == allocated[37]
    with pytest.raises(RuntimeError, match="All 500"):
        bank.get_or_claim(conn, "auth0|one-extra-customer")
    conn.close()


def test_edit_bills_only_affects_owner_and_survives_restart(tmp_path):
    db_path = tmp_path / "catalog.sqlite3"
    conn = connection(db_path)
    bank.initialize(conn, count=3)
    a = bank.get_or_claim(conn, "auth0|alice")
    b = bank.get_or_claim(conn, "auth0|bob")
    assert a["portfolio_id"] != b["portfolio_id"]
    values = {
        "payee": "Fiber broadband", "payment_amount": 89.99,
        "payment_date": (date.today()+timedelta(days=6)).isoformat(),
        "category": "internet", "frequency": "monthly",
    }
    created = bank.upsert_bill(conn, "auth0|alice", values)
    bill_id = created["bill_id"]
    assert created["payment_amount"] == 89.99
    with pytest.raises(ValueError):
        bank.delete_bill(conn, "auth0|bob", bill_id)
    assert bank.get(conn, "auth0|bob") == b
    edited = bank.upsert_bill(conn, "auth0|alice", {**values, "payment_amount": 70.5}, bill_id)
    assert edited["payment_amount"] == 70.5
    conn.close()
    conn = connection(db_path)
    assert bank.get(conn, "auth0|alice")["app_bills"][bill_id]["payment_amount"] == 70.5
    assert bank.delete_bill(conn, "auth0|alice", bill_id)
    assert bill_id not in bank.get(conn, "auth0|alice")["app_bills"]
    conn.close()


def test_simulated_transfer_is_idempotent_and_protected(tmp_path):
    conn = connection(tmp_path / "bank.sqlite3")
    bank.initialize(conn, count=3)
    bank.get_or_claim(conn, "auth0|alice")
    before = bank.get(conn, "auth0|alice")
    checking = before["accounts"]["checking"]["balance"]
    savings = before["accounts"]["savings"]["balance"]
    reserve = max(0, savings - 125)
    r = bank.simulated_transfer(conn, "auth0|alice", 100, "unique-key-001", reserve)
    assert r["simulation"] is True
    assert r["status"] == "simulated_posted"
    assert r["balances"]["checking"] == round(checking + 100, 2)
    assert r["balances"]["savings"] == round(savings - 100, 2)
    assert bank.simulated_transfer(conn, "auth0|alice", 100, "unique-key-001", reserve)["previous_request"]
    with pytest.raises(ValueError, match="idempotency"):
        bank.simulated_transfer(conn, "auth0|alice", 101, "unique-key-001", reserve)
    with pytest.raises(ValueError, match="reserve"):
        bank.simulated_transfer(conn, "auth0|alice", 100, "unique-key-002", savings)
    after = bank.get(conn, "auth0|alice")
    assert len(after["transactions"]) == len(before["transactions"]) + 2
    assert after["accounts"]["checking"]["balance"] == round(checking + 100, 2)
    conn.close()
