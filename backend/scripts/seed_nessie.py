#!/usr/bin/env python3
"""Populate CreditPilot's fictional Nessie demo with repeatable seed data."""
import argparse
from datetime import date, timedelta
import json
import os
from pathlib import Path
import secrets
import sys
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

BACKEND = Path(__file__).resolve().parents[1]
MANIFEST = BACKEND / "seed_manifest.json"
DEFAULT_URL = "https://prod-api.nessieisreal.com"


def env():
    path = BACKEND / ".env"
    if path.exists():
        for line in path.read_text(encoding="utf8").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.strip().split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


class Nessie:
    def __init__(self):
        self.key = os.getenv("NESSIE_API_KEY", "")
        self.base = os.getenv("NESSIE_BASE_URL", DEFAULT_URL).rstrip("/")
        parsed = urlparse(self.base)
        if parsed.scheme != "https" or not parsed.netloc or parsed.path not in ("", "/"):
            raise ValueError("Use NESSIE_BASE_URL=https://prod-api.nessieisreal.com (HTTPS required)")
        if not self.key or self.key == "YOUR_NESSIE_SANDBOX_API_KEY":
            raise ValueError("Put NESSIE_API_KEY in backend/.env first")

    def request(self, method, path, body=None):
        # Never print the full URL: Nessie authenticates using the key query parameter.
        url = self.base + path + "?" + urlencode({"key": self.key})
        data = json.dumps(body).encode("utf8") if body is not None else None
        req = Request(url, data=data, method=method,
                      headers={"Content-Type": "application/json"})
        try:
            with urlopen(req, timeout=20) as result:
                raw = result.read().decode("utf8")
                return json.loads(raw) if raw.strip() else {}
        except HTTPError as e:
            msg = e.read().decode("utf8", errors="replace")[:400].replace(self.key, "[REDACTED]")
            raise RuntimeError(method + " " + path + " HTTP " + str(e.code) + ": " + msg) from None
        except URLError:
            raise RuntimeError(method + " " + path + ": Nessie connection failed") from None

    def get(self, path):
        return self.request("GET", path)

    def post(self, path, body):
        return self.request("POST", path, body)

    def put(self, path, body):
        return self.request("PUT", path, body)


def listing(response):
    if isinstance(response, list):
        return response
    if isinstance(response, dict):
        for key in ("data", "results", "content", "customers", "accounts", "bills", "merchants"):
            if isinstance(response.get(key), list):
                return response[key]
    raise RuntimeError("Unexpected Nessie list response")


def save(state):
    temp = MANIFEST.with_suffix(".json.tmp")
    temp.write_text(json.dumps(state, indent=2) + "\n", encoding="utf8")
    temp.replace(MANIFEST)


def upsert(client, state, group, label, collection, endpoint, payload, unique_key):
    saved = state.setdefault("ids", {}).setdefault(group, {})
    if label in saved:
        print("REUSE", group, label, saved[label])
        return saved[label]
    matches = [x for x in listing(client.get(collection))
               if isinstance(x, dict) and x.get(unique_key) == payload[unique_key]]
    if len(matches) > 1:
        raise RuntimeError("Multiple records for " + group + "/" + label)
    if matches:
        identity = matches[0].get("_id")
    else:
        created = client.post(endpoint, payload)
        obj = created.get("objectCreated", {}) if isinstance(created, dict) else {}
        identity = obj.get("_id") if isinstance(obj, dict) else None
        if not identity:
            matches = [x for x in listing(client.get(collection))
                       if isinstance(x, dict) and x.get(unique_key) == payload[unique_key]]
            identity = matches[0].get("_id") if len(matches) == 1 else None
    if not identity:
        raise RuntimeError("Could not find new ID for " + group + "/" + label)
    saved[label] = identity
    save(state)
    print("READY", group, label, identity)
    return identity


def build(state):
    start = date.fromisoformat(state["created_on"])
    tag = "CP-" + state["seed_id"]
    address = {"street_number": "100", "street_name": "Demo Way",
               "city": "Gainesville", "state": "FL", "zip": "32601"}
    customers = {
        "sarah": {"first_name": "Sarah", "last_name": "Demo" + state["seed_id"], "address": address},
        "jamie": {"first_name": "Jamie", "last_name": "Partner" + state["seed_id"], "address": address}}
    accounts = {
        "checking": ("sarah", "Checking", 500),
        "savings": ("sarah", "Savings", 1200),
        "card_a": ("sarah", "Credit Card", 750),
        "card_b": ("sarah", "Credit Card", 200),
        "joint_demo": ("sarah", "Checking", 2000),
        "partner_checking": ("jamie", "Checking", 350)}
    merchants = {
        "grocery": {"name": tag + "-Grocery", "category": "Groceries", "address": address},
        "gas": {"name": tag + "-Fuel", "category": "Gas", "address": address},
        "restaurant": {"name": tag + "-Cafe", "category": "Dining", "address": address}}
    bills = {"rent": ("Apartment Rent", 400, 3),
             "electricity": ("Electric Utility", 150, 7),
             "internet": ("Internet Provider", 100, 12)}
    return tag, start, customers, accounts, merchants, bills


def run(apply=False, verify=False):
    env()
    if MANIFEST.exists():
        state = json.loads(MANIFEST.read_text(encoding="utf8"))
    else:
        if verify:
            raise ValueError("No seed_manifest.json found; seed first")
        state = {"seed_id": date.today().strftime("%Y%m%d") + "-" + secrets.token_hex(3),
                 "created_on": date.today().isoformat(), "ids": {}}
    tag, start, customers, accounts, merchants, bills = build(state)
    if not apply and not verify:
        print("DRY RUN (nothing inserted): 2 customers, 6 accounts, 3 merchants, 3 bills")
        for name, (owner, kind, amount) in accounts.items():
            print("  ", name, kind, "USD", amount)
        for name, (_, amount, offset) in bills.items():
            print("  ", name, "USD", amount, "due", start + timedelta(days=offset))
        print("Run: py backend\\scripts\\seed_nessie.py --apply")
        return

    api = Nessie()
    if verify:
        for group, prefix in (("customers", "/customers/"), ("accounts", "/accounts/")):
            for name, identity in state.get("ids", {}).get(group, {}).items():
                response = api.get(prefix + identity)
                print(group, name, "OK" if response.get("_id") == identity else "CHECK")
        return

    save(state)  # preserve seed ID even if a later request fails
    # The original seeder accidentally matched Sarah and Jamie by the same last name.
    # Repair saved references against Nessie before creating other records.
    stored_customers = state.setdefault("ids", {}).setdefault("customers", {})
    for name, expected in customers.items():
        old_id = stored_customers.get(name)
        if not old_id:
            continue
        found = api.get("/customers/" + old_id)
        if found.get("first_name") != expected["first_name"]:
            print("REPAIR customer reference:", name, "did not match saved customer")
            stored_customers.pop(name)
            save(state)
    for name, value in customers.items():
        upsert(api, state, "customers", name, "/customers", "/customers", value, "last_name")
    for name, (owner, kind, amount) in accounts.items():
        owner_id = state["ids"]["customers"][owner]
        saved_account = state.setdefault("ids", {}).setdefault("accounts", {}).get(name)
        if saved_account:
            account = api.get("/accounts/" + saved_account)
            if account.get("customer_id") and account["customer_id"] != owner_id:
                print("REPAIR account reference:", name, "belongs to another customer")
                state["ids"]["accounts"].pop(name)
                save(state)
        path = "/customers/" + owner_id + "/accounts"
        payload = {"type": kind, "nickname": tag + "-" + name,
                   "rewards": 0, "balance": amount}
        upsert(api, state, "accounts", name, path, path, payload, "nickname")
    for name, value in merchants.items():
        upsert(api, state, "merchants", name, "/merchants", "/merchants", value, "name")
    check_id = state["ids"]["accounts"]["checking"]
    bill_path = "/accounts/" + check_id + "/bills"
    for name, (payee, amount, days) in bills.items():
        due = start + timedelta(days=days)
        payload = {"status": "pending", "payee": payee,
                   "nickname": tag + "-" + name,
                   "payment_date": due.isoformat(),
                   "recurring_date": due.day,
                   "upcoming_payment_date": due.isoformat(),
                   "payment_amount": amount}
        existing_id = state.get("ids", {}).get("bills", {}).get(name)
        if existing_id:
            # The old script posted an incomplete rent bill. GET collection then fails.
            # Update it directly by saved ID before attempting to list bills.
            try:
                api.get("/bills/" + existing_id)
            except RuntimeError as error:
                if "validation errors for Bill" not in str(error):
                    raise
                print("REPAIR existing incomplete bill:", name)
                api.put("/bills/" + existing_id, payload)
                try:
                    api.get("/bills/" + existing_id)
                except RuntimeError as repair_error:
                    raise RuntimeError(
                        "Nessie cannot read the existing malformed " + name +
                        " bill after PUT. The sandbox may be ignoring the new date "
                        "fields. Do not reseed or delete it blindly. Inspect bill " +
                        existing_id + " in Nessie; error: " + str(repair_error)
                    ) from None
        upsert(api, state, "bills", name, bill_path, bill_path, payload, "nickname")
        # New records must also be readable; otherwise stop before creating more.
        try:
            api.get("/bills/" + state["ids"]["bills"][name])
        except RuntimeError as read_error:
            raise RuntimeError(
                "Nessie created " + name + " but cannot read it. "
                "Stop seeding and inspect bill data: " + str(read_error)
            ) from None

    ids = state["ids"]
    state["app_scenario"] = {
        "note": "Fictional app-only metadata, not real credit reporting or joint-account controls",
        "future_bills": {"horizon_days": 14, "shortfall_usd": 150},
        "card_a": {"account_id": ids["accounts"]["card_a"], "limit_usd": 1000,
                   "rewards": {"groceries": 0.03, "gas": 0.01}, "statement_closes_in_days": 9},
        "card_b": {"account_id": ids["accounts"]["card_b"], "limit_usd": 2000,
                   "rewards": {"groceries": 0.02, "gas": 0.02}, "statement_closes_in_days": 13},
        "autopay": {"target_utilization": 0.29, "requires_approval": True},
        "joint": {"account_id": ids["accounts"]["joint_demo"],
                  "partner_id": ids["customers"]["jamie"],
                  "proposed_unusual_payment_usd": 850,
                  "in_app_payments_only": True},
        "emergency": {"unexpected_expense_usd": 1000, "reserve_usd": 300}}
    save(state)
    print("SUCCESS: Nessie records inserted; IDs in backend/seed_manifest.json")
    print("No transfers or payments were initiated. Verify with --verify.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    try:
        run(args.apply, args.verify)
    except (RuntimeError, ValueError, OSError) as e:
        print("ERROR:", e, file=sys.stderr)
        sys.exit(1)
