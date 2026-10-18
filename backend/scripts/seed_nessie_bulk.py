#!/usr/bin/env python3
"""Seed up to 500 fictional CreditPilot customer accounts in the Nessie sandbox.

Default: 500 customers with one Checking account each (500 real Nessie accounts).
--full-portfolio: copy all 4-8 accounts from each synthetic demo portfolio.
No bills, transfers, purchases, deposits, or actual money movements are created.

Run from repository root:
    python backend/scripts/seed_nessie_bulk.py
    python backend/scripts/seed_nessie_bulk.py --apply
    python backend/scripts/seed_nessie_bulk.py --verify
"""
import argparse
from datetime import date
import hashlib
import json
from pathlib import Path
import sys
import time

from seed_nessie import BACKEND, Nessie, env, listing
from synthetic_bank import CATALOG_SIZE, _make_profile

MANIFEST = BACKEND / "nessie_bulk_manifest.json"
ADDRESS = {
    "street_number": "100",
    "street_name": "Demo Way",
    "city": "Gainesville",
    "state": "FL",
    "zip": "32601",
}


def save(state):
    temp = MANIFEST.with_suffix(".json.tmp")
    temp.write_text(json.dumps(state, indent=2) + "\n", encoding="utf8")
    temp.replace(MANIFEST)


def get(client, path):
    """Retry read-only requests when the Nessie sandbox is busy."""
    for attempt in range(6):
        try:
            return client.get(path)
        except RuntimeError as error:
            message = str(error)
            transient = any("HTTP " + str(code) in message for code in (429, 500, 502, 503, 504))
            if not transient or attempt == 5:
                raise
            time.sleep(min(2 ** attempt, 20))
    raise RuntimeError("Read retry limit exceeded")


def matching(rows, field, value):
    matches = [row for row in rows if isinstance(row, dict) and row.get(field) == value]
    if len(matches) > 1:
        raise RuntimeError("Multiple Nessie records match " + field + "=" + str(value))
    return matches[0] if matches else None


def recover_post(client, path, payload, lookup_path, unique_field):
    """Never blindly retry a POST: recover by a unique name after ambiguity."""
    error = None
    identity = None
    try:
        response = client.post(path, payload)
        if isinstance(response, dict):
            created = response.get("objectCreated")
            if isinstance(created, dict):
                identity = created.get("_id")
    except RuntimeError as exc:
        error = exc

    if not identity:
        found = matching(listing(get(client, lookup_path)), unique_field, payload[unique_field])
        if found:
            identity = found.get("_id")
    if not identity:
        if error is not None:
            raise error
        raise RuntimeError("Nessie did not return or expose new " + unique_field)
    return identity


def setup(client, full_portfolio):
    fingerprint = hashlib.sha256(client.key.encode("utf8")).hexdigest()[:8]
    if MANIFEST.exists():
        state = json.loads(MANIFEST.read_text(encoding="utf8"))
        if state.get("sandbox_fingerprint") != fingerprint:
            raise ValueError("This manifest belongs to a different Nessie API key")
        if bool(state.get("full_portfolio")) != full_portfolio:
            raise ValueError("Portfolio mode differs from previous run. Keep the same flag.")
    else:
        state = {
            "version": 1,
            "sandbox_fingerprint": fingerprint,
            "as_of": date.today().isoformat(),
            "full_portfolio": full_portfolio,
            "customers": {},
            "accounts": {},
        }
        save(state)
    return state, fingerprint


def customer_name(fingerprint, slot):
    return "CP" + fingerprint + ("P%04d" % slot)


def account_nickname(fingerprint, slot, key):
    return "CP" + fingerprint + ("-%04d-" % slot) + key


def targets(slot, as_of, full_portfolio):
    profile = _make_profile(slot, as_of)
    if full_portfolio:
        return profile["accounts"]
    return {"checking": profile["accounts"]["checking"]}


def create_all(client, state, fingerprint, count, delay):
    known_customers = listing(get(client, "/customers"))
    customer_by_name = {
        row.get("last_name"): row for row in known_customers if isinstance(row, dict)
    }
    created_accounts = 0
    for slot in range(count):
        slot_key = str(slot)
        last_name = customer_name(fingerprint, slot)
        customer_id = state["customers"].get(slot_key)
        remote_customer = customer_by_name.get(last_name)

        if customer_id and remote_customer and remote_customer.get("_id") != customer_id:
            raise RuntimeError("Customer ID mismatch in slot " + slot_key)
        if not customer_id and remote_customer:
            customer_id = remote_customer.get("_id")
        if not customer_id:
            customer_id = recover_post(
                client,
                "/customers",
                {"first_name": "CreditPilot", "last_name": last_name, "address": ADDRESS},
                "/customers",
                "last_name",
            )
            time.sleep(delay)
        state["customers"][slot_key] = customer_id
        save(state)

        expected = targets(slot, date.fromisoformat(state["as_of"]), state["full_portfolio"])
        existing = state["accounts"].setdefault(slot_key, {})
        if len(existing) == len(expected) and all(key in existing for key in expected):
            if (slot + 1) % 25 == 0 or slot + 1 == count:
                print(f"Progress: {slot + 1}/{count} customers, IDs saved")
            continue

        remote_accounts = listing(get(client, "/customers/" + customer_id + "/accounts"))
        for key, values in expected.items():
            nickname = account_nickname(fingerprint, slot, key)
            remote_account = matching(remote_accounts, "nickname", nickname)
            identity = existing.get(key)
            if identity and remote_account and remote_account.get("_id") != identity:
                raise RuntimeError("Account ID mismatch in slot " + slot_key + "/" + key)
            if not identity and remote_account:
                identity = remote_account.get("_id")
            if not identity:
                payload = {
                    "type": values["type"],
                    "nickname": nickname,
                    "rewards": 0,
                    "balance": values["balance"],
                }
                identity = recover_post(
                    client,
                    "/customers/" + customer_id + "/accounts",
                    payload,
                    "/customers/" + customer_id + "/accounts",
                    "nickname",
                )
                created_accounts += 1
                time.sleep(delay)
            existing[key] = identity
            save(state)

        if (slot + 1) % 25 == 0 or slot + 1 == count:
            total_accounts = sum(len(value) for value in state["accounts"].values())
            print(f"Progress: {slot + 1}/{count} customers, {total_accounts} accounts saved")
    return created_accounts


def verify(client, state, fingerprint, count):
    failures = []
    accounts_seen = 0
    for slot in range(count):
        slot_key = str(slot)
        customer_id = state["customers"].get(slot_key)
        if not customer_id:
            failures.append("customer slot " + slot_key + " missing from manifest")
            continue
        remote = get(client, "/customers/" + customer_id)
        if remote.get("_id") != customer_id or remote.get("last_name") != customer_name(fingerprint, slot):
            failures.append("customer slot " + slot_key + " mismatch")
            continue
        actual = listing(get(client, "/customers/" + customer_id + "/accounts"))
        by_name = {row.get("nickname"): row for row in actual if isinstance(row, dict)}
        expected = targets(slot, date.fromisoformat(state["as_of"]), state["full_portfolio"])
        for key in expected:
            identity = state["accounts"].get(slot_key, {}).get(key)
            name = account_nickname(fingerprint, slot, key)
            if not identity or by_name.get(name, {}).get("_id") != identity:
                failures.append("account " + slot_key + "/" + key + " missing or mismatched")
            else:
                accounts_seen += 1
        if (slot + 1) % 100 == 0:
            print(f"Verified: {slot + 1}/{count} customers")
    print(f"Nessie verification: {count - len({x for x in failures if x.startswith('customer ')})}/{count} customer slots inspected; {accounts_seen} accounts confirmed")
    if failures:
        for item in failures[:10]:
            print("FAILED:", item)
        raise RuntimeError(str(len(failures)) + " verification errors (showing first 10)")
    print("SUCCESS: all requested accounts verified in Nessie")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--apply", action="store_true", help="Write accounts to your Nessie sandbox")
    modes.add_argument("--verify", action="store_true", help="Read back and verify saved accounts")
    parser.add_argument("--count", type=int, default=500, help="Number of customer portfolios, 1-500")
    parser.add_argument("--full-portfolio", action="store_true", help="Create 4-8 accounts per customer instead of one")
    parser.add_argument("--delay", type=float, default=0.15, help="Seconds between writes (default: 0.15)")
    args = parser.parse_args()
    if not 1 <= args.count <= CATALOG_SIZE or not 0 <= args.delay <= 30:
        parser.error("--count must be 1-500 and --delay must be 0-30")

    if not args.apply and not args.verify:
        print(f"DRY RUN: {args.count} customers; " +
              ("4-8 Nessie accounts each" if args.full_portfolio else f"{args.count} Nessie checking accounts"))
        print("No data was uploaded. Use --apply to insert and --verify to confirm.")
        return
    env()
    client = Nessie()
    if client.key.startswith("YOUR_"):
        raise ValueError("Replace the placeholder NESSIE_API_KEY in backend/.env")
    if args.verify and not MANIFEST.exists():
        raise ValueError("No manifest: run --apply first")
    state, fingerprint = setup(client, args.full_portfolio)
    if args.apply:
        added = create_all(client, state, fingerprint, args.count, args.delay)
        print(f"APPLY finished. New accounts created in this run: {added}.")
        print("Saved account IDs: backend/nessie_bulk_manifest.json")
        print("Run --verify to confirm Nessie's records.")
    else:
        verify(client, state, fingerprint, args.count)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError) as error:
        print("ERROR:", error, file=sys.stderr)
        sys.exit(1)
