"""Deterministic, isolated fictional retail banking portfolios.

Creates a catalog of 500 distinct *customer portfolios*, with 4-8 synthetic
bank/credit accounts per portfolio, 12-25 upcoming bills and 90-160 ledger
entries. Once a verified Auth0 subject first signs in, a free portfolio is
claimed atomically and remains assigned to that subject forever.

NO passwords, user-provided names, email addresses, SSNs or real bank data
are used to generate finances. This is an interactive demo dataset, not Nessie
or an issuer-provided banking connection.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
import hashlib
import json
import random
import sqlite3
from decimal import Decimal
from typing import Optional

CATALOG_SIZE = 500
CATALOG_VERSION = 1
DATA_SOURCE = "synthetic_banking_demo"

# All institutions, products, offers, APRs and rewards below are fictional.
CARD_PRODUCTS = (
    ("Harbor Everyday Cash", "Harbor Community Bank", "Visa",
     {"groceries": .04, "gas": .02, "dining": .02, "other": .01}),
    ("Summit Travel Miles", "Summit Financial", "Mastercard",
     {"travel": .05, "dining": .03, "groceries": .01, "other": .015}),
    ("Cedar Dining Rewards", "Cedar Credit Union", "Visa",
     {"dining": .04, "groceries": .03, "other": .01}),
    ("Northstar Student Cash", "Northstar Bank", "Visa",
     {"groceries": .03, "gas": .03, "dining": .02, "other": .01}),
    ("Pioneer Fuel & Transit", "Pioneer Financial", "Mastercard",
     {"gas": .05, "transit": .04, "travel": .02, "other": .01}),
    ("Bluehaven Everyday Plus", "Bluehaven Bank", "Visa",
     {"groceries": .03, "travel": .03, "dining": .03, "other": .015}),
    ("Meridian Flexible Rewards", "Meridian Credit Union", "Mastercard",
     {"groceries": .025, "gas": .025, "dining": .025, "other": .015}),
    ("Willow Cash Preferred", "Willow Financial", "Visa",
     {"groceries": .05, "streaming": .06, "dining": .02, "other": .01}),
)

BILL_TEMPLATES = (
    ("Rent / mortgage", "housing", (850, 2650)),
    ("Electric & gas", "utilities", (65, 235)),
    ("Water & sewer", "utilities", (30, 90)),
    ("Internet", "internet", (45, 110)),
    ("Mobile service", "phone", (35, 145)),
    ("Car insurance", "insurance", (80, 225)),
    ("Health insurance", "insurance", (90, 450)),
    ("Auto loan", "loan", (180, 610)),
    ("Student loan", "loan", (65, 360)),
    ("Gym membership", "fitness", (15, 75)),
    ("Streaming package", "streaming", (9, 42)),
    ("Music subscription", "streaming", (8, 18)),
    ("Cloud storage", "software", (3, 19)),
    ("Video games", "entertainment", (9, 39)),
    ("Pet insurance", "insurance", (22, 85)),
    ("Daycare / school", "education", (210, 980)),
    ("Property insurance", "insurance", (65, 210)),
    ("Home security", "utilities", (12, 45)),
    ("Transit pass", "transit", (45, 140)),
    ("Parking", "transportation", (40, 225)),
    ("Meal plan", "food", (65, 210)),
    ("Storage unit", "housing", (49, 180)),
    ("Professional membership", "membership", (12, 65)),
    ("Dental coverage", "insurance", (14, 56)),
    ("Charitable donation", "giving", (10, 95)),
    ("Home maintenance", "housing", (35, 210)),
    ("Child activities", "education", (30, 180)),
    ("Electric vehicle charging", "transportation", (19, 105)),
)

MERCHANTS = (
    ("Fresh Fields Market", "groceries", 12, 220),
    ("Neighborhood Pharmacy", "health", 8, 95),
    ("Corner Coffee", "dining", 3, 19),
    ("Bistro Lane", "dining", 17, 105),
    ("Fuel Station", "gas", 19, 85),
    ("Metro Transit", "transit", 3, 49),
    ("Home Supply Center", "shopping", 15, 285),
    ("Online Marketplace", "shopping", 9, 345),
    ("Movie House", "entertainment", 15, 80),
    ("Ride Share", "travel", 11, 75),
    ("Hardware & Garden", "shopping", 12, 160),
    ("City Parking", "transportation", 6, 35),
    ("Bookshop", "education", 8, 75),
    ("Bakery & Deli", "dining", 5, 39),
)

def _dollars(value: float) -> float:
    return float(Decimal(str(value)).quantize(Decimal("0.01")))


def _make_profile(slot: int, as_of: date) -> dict:
    rng = random.Random(194_861 + slot * 100_003)
    persona = rng.choice(("student", "early_career", "family", "freelance", "retiree"))
    income_base = {
        "student": (1200, 3400),
        "early_career": (3200, 7500),
        "family": (5300, 13200),
        "freelance": (1800, 9800),
        "retiree": (2100, 6100),
    }
    income = _dollars(rng.uniform(*income_base[persona]))
    check_balance = _dollars(rng.uniform(150, max(900, income * 1.2)))
    save_balance = _dollars(rng.uniform(250, max(1200, income * 6)))
    institution = rng.choice(("Harbor Community Bank", "Pioneer Financial",
                              "Summit Financial", "Northstar Bank",
                              "Cedar Credit Union", "Meridian Credit Union"))

    accounts = {}
    ids = {}
    scenarios = {}
    def add_account(key: str, label: str, kind: str, balance: float,
                    issuer: str, last4: int, **extra):
        identity = f"CP{slot:04d}-{key}"
        item = {"_id": identity, "kind": key, "nickname": label,
                "type": kind, "balance": _dollars(balance), "institution": issuer,
                "last4": str(last4).zfill(4), "currency": "USD",
                "source": DATA_SOURCE}
        item.update(extra)
        accounts[key] = item
        ids[key] = identity

    last4_seed = rng.randint(1000, 9999)
    add_account("checking", "Everyday Checking", "Checking",
                check_balance, institution, last4_seed)
    add_account("savings", "High-Yield Savings", "Savings",
                save_balance, institution, (last4_seed + 57) % 10000)
    joint_bal = _dollars(rng.uniform(260, 5500))
    add_account("joint_demo", "Household Shared Checking", "Checking",
                joint_bal, institution, (last4_seed + 103) % 10000,
                access="simulated_joint")
    add_account("partner_checking", "Secondary Checking", "Checking",
                _dollars(rng.uniform(150, 3500)), institution,
                (last4_seed + 167) % 10000)

    n_cards = rng.randint(2, 4)
    selection = rng.sample(CARD_PRODUCTS, n_cards)
    for i, (product, bank, network, rates) in enumerate(selection):
        key = f"card_{i+1}"
        limit = rng.choice((750, 1200, 1500, 2500, 3500, 5000,
                            7500, 10000, 12000, 18000))
        utilization = rng.uniform(.03, .88)
        balance = _dollars(limit * utilization)
        statement_days = rng.randint(3, 27)
        last4 = (last4_seed + 1000 + i * 211 + slot * 3) % 10000
        add_account(key, product, "Credit Card", balance, bank, last4,
                    network=network, credit_limit=limit,
                    statement_closes_in_days=statement_days)
        scenarios[key] = {
            "limit_usd": limit,
            "rewards": rates,
            "statement_closes_in_days": statement_days,
            "display_name": product,
            "issuer": bank,
            "last4": str(last4).zfill(4),
            "network": network,
            "reward_rates_are_simulated": True,
        }

    # A broad but consistent future commitment list per persona.
    n_bills = rng.randint(12, 25)
    source_templates = list(BILL_TEMPLATES)
    rng.shuffle(source_templates)
    chosen = source_templates[:n_bills]
    if not any(category == "housing" for _, category, _ in chosen):
        chosen[0] = BILL_TEMPLATES[0]
    app_bills = {}
    for i, (payee, category, (lower, upper)) in enumerate(chosen):
        # Stable varied next due date; each date is initially within 1..45 days.
        due = as_of + timedelta(days=rng.randint(1, 45))
        cost = _dollars(rng.uniform(lower, upper))
        bill_id = f"CP{slot:04d}-bill-{i+1:03d}"
        app_bills[bill_id] = {
            "bill_id": bill_id,
            "payee": payee,
            "nickname": payee,
            "category": category,
            "payment_amount": cost,
            "payment_date": due.isoformat(),
            "upcoming_payment_date": due.isoformat(),
            "recurring_date": due.day,
            "frequency": "monthly",
            "status": "pending",
            "account_id": ids["checking"],
            "source": DATA_SOURCE,
        }

    transactions = []
    tx_count = rng.randint(90, 160)
    for idx in range(tx_count):
        merchant, category, min_cost, max_cost = rng.choice(MERCHANTS)
        days = rng.randint(0, 94)
        when = as_of - timedelta(days=days)
        value = _dollars(rng.uniform(min_cost, max_cost))
        paid_by = rng.choice(["checking"] + list(scenarios))
        tx_id = f"CP{slot:04d}-txn-{idx+1:04d}"
        transactions.append({
            "id": tx_id, "account_id": ids[paid_by], "account_kind": paid_by,
            "merchant": merchant, "category": category, "direction": "debit",
            "amount": value, "date": when.isoformat(), "status": "posted",
            "source": DATA_SOURCE,
        })
    for idx in range(3):
        when = as_of - timedelta(days=idx * 28 + rng.randint(0, 5))
        transactions.append({
            "id": f"CP{slot:04d}-income-{idx+1}",
            "account_id": ids["checking"], "account_kind": "checking",
            "merchant": "Payroll / Income", "category": "income",
            "direction": "credit", "amount": income, "date": when.isoformat(),
            "status": "posted", "source": DATA_SOURCE,
        })
    transactions.sort(key=lambda t: (t["date"], t["id"]), reverse=True)

    return {
        "catalog_version": CATALOG_VERSION,
        "portfolio_id": f"CP{slot:04d}",
        "source": DATA_SOURCE,
        "persona": persona,
        "scenario_description": "Fictional balances, rates and commitments, not a linked bank.",
        "monthly_income": income,
        "as_of": as_of.isoformat(),
        "accounts": accounts,
        "ids": {"accounts": ids},
        "app_scenario": scenarios,
        "app_bills": app_bills,
        "transactions": transactions,
    }


def initialize(conn: sqlite3.Connection, count: int = CATALOG_SIZE, as_of: Optional[date] = None) -> None:
    """Build the dataset once without overwriting claims or user changes."""
    conn.execute("""CREATE TABLE IF NOT EXISTS synthetic_profiles (
        slot INTEGER PRIMARY KEY,
        owner_sub TEXT UNIQUE,
        payload TEXT NOT NULL,
        assigned_at TEXT
    )""")
    existing = conn.execute("SELECT COUNT(*) FROM synthetic_profiles").fetchone()[0]
    if existing == 0:
        today = as_of or date.today()
        rows = ((slot, json.dumps(_make_profile(slot, today), separators=(",", ":")))
                for slot in range(count))
        conn.executemany(
            "INSERT INTO synthetic_profiles(slot, payload) VALUES (?,?)", rows
        )
    conn.commit()


def _fingerprint(subject: str) -> int:
    return int.from_bytes(hashlib.sha256(subject.encode("utf-8")).digest()[:8], "big")


def get_or_claim(conn: sqlite3.Connection, subject: str) -> dict:
    if not subject or subject.startswith("demo-") or len(subject) > 256:
        raise ValueError("Verified Auth0 subject required")
    # BEGIN IMMEDIATE prevents concurrent signups from claiming the same slot.
    conn.execute("BEGIN IMMEDIATE")
    try:
        existing = conn.execute(
            "SELECT payload FROM synthetic_profiles WHERE owner_sub=?", (subject,)
        ).fetchone()
        if existing:
            conn.commit()
            return json.loads(existing[0])
        count = conn.execute("SELECT COUNT(*) FROM synthetic_profiles").fetchone()[0]
        if not count:
            raise RuntimeError("Synthetic catalog is not initialized")
        start = _fingerprint(subject) % count
        # Simple index-aware linear probing; preserves deterministic first choice
        # while guaranteeing uniqueness under collisions.
        row = conn.execute(
            "SELECT slot, payload FROM synthetic_profiles "
            "WHERE owner_sub IS NULL AND slot>=? ORDER BY slot LIMIT 1",
            (start,)
        ).fetchone()
        if row is None:
            row = conn.execute(
                "SELECT slot, payload FROM synthetic_profiles "
                "WHERE owner_sub IS NULL ORDER BY slot LIMIT 1"
            ).fetchone()
        if row is None:
            raise RuntimeError("All 500 demo portfolios are assigned")
        updated = conn.execute(
            "UPDATE synthetic_profiles SET owner_sub=?, assigned_at=? "
            "WHERE slot=? AND owner_sub IS NULL",
            (subject, datetime.now(timezone.utc).isoformat(), row[0])
        )
        if updated.rowcount != 1:
            raise RuntimeError("Concurrent portfolio allocation failed")
        conn.commit()
        return json.loads(row[1])
    except Exception:
        conn.rollback()
        raise


def get(conn: sqlite3.Connection, subject: str) -> Optional[dict]:
    result = conn.execute(
        "SELECT payload FROM synthetic_profiles WHERE owner_sub=?", (subject,)
    ).fetchone()
    return json.loads(result[0]) if result else None


def stats(conn: sqlite3.Connection) -> dict:
    total, claimed = conn.execute(
        "SELECT COUNT(*), COUNT(owner_sub) FROM synthetic_profiles"
    ).fetchone()
    return {"profiles_total": total, "profiles_claimed": claimed,
            "profiles_available": total - claimed,
            "source": DATA_SOURCE}


def _mutate(conn: sqlite3.Connection, subject: str, operation) -> dict:
    conn.execute("BEGIN IMMEDIATE")
    try:
        row = conn.execute(
            "SELECT slot, payload FROM synthetic_profiles WHERE owner_sub=?",
            (subject,)
        ).fetchone()
        if row is None:
            raise ValueError("No assigned fictional portfolio")
        profile = json.loads(row[1])
        result = operation(profile)
        conn.execute(
            "UPDATE synthetic_profiles SET payload=? WHERE slot=? AND owner_sub=?",
            (json.dumps(profile, separators=(",", ":")), row[0], subject)
        )
        conn.commit()
        return result
    except Exception:
        conn.rollback()
        raise


def upsert_bill(conn: sqlite3.Connection, subject: str, values: dict,
                bill_id: Optional[str] = None) -> dict:
    def apply(profile):
        bills = profile["app_bills"]
        target = bill_id or f"{profile['portfolio_id']}-bill-custom-{len(bills)+1:03d}"
        if bill_id and bill_id not in bills:
            raise ValueError("Bill does not belong to authenticated user")
        if not bill_id:
            while target in bills:
                target += "x"
        due = date.fromisoformat(values["payment_date"])
        old = bills.get(target, {})
        item = {
            **old, "bill_id": target, "payee": values["payee"],
            "nickname": values["payee"], "payment_amount": _dollars(values["payment_amount"]),
            "payment_date": due.isoformat(),
            "upcoming_payment_date": due.isoformat(),
            "recurring_date": due.day,
            "category": values["category"], "frequency": values["frequency"],
            "status": "pending", "account_id": profile["ids"]["accounts"]["checking"],
            "source": DATA_SOURCE,
        }
        bills[target] = item
        return item
    return _mutate(conn, subject, apply)


def delete_bill(conn: sqlite3.Connection, subject: str, bill_id: str) -> bool:
    def apply(profile):
        if bill_id not in profile["app_bills"]:
            raise ValueError("Bill does not belong to authenticated user")
        del profile["app_bills"][bill_id]
        return True
    return _mutate(conn, subject, apply)


def revise_income(conn: sqlite3.Connection, subject: str, income: float) -> dict:
    def apply(profile):
        profile["monthly_income"] = _dollars(income)
        return {"monthly_income": profile["monthly_income"], "source": DATA_SOURCE}
    return _mutate(conn, subject, apply)
