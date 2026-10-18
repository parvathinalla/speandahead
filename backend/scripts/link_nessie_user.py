#!/usr/bin/env python3
"""Associate a pre-created Auth0 login with one slot in the 500-customer Nessie seed."""
import argparse
import json
import os
from pathlib import Path
import sys
import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from dotenv import load_dotenv
from nessie_links import NessieLinkStore


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subject", required=True, help="Exact Auth0 user ID (sub)")
    parser.add_argument("--slot", type=int, required=True, help="Nessie bulk seed slot, 0 through 499")
    args = parser.parse_args()
    if not 0 <= args.slot < 500:
        parser.error("--slot must be between 0 and 499")
    load_dotenv(ROOT / ".env")
    data = json.loads((ROOT / "nessie_bulk_manifest.json").read_text(encoding="utf-8"))
    slot = str(args.slot)
    customer = data.get("customers", {}).get(slot)
    accounts = data.get("accounts", {}).get(slot, {})
    if not customer or not accounts.get("checking"):
        parser.error("Slot not seeded. Run seed_nessie_bulk.py --apply first.")
    NessieLinkStore.validate_mapping(customer, accounts)
    base = os.getenv("NESSIE_BASE_URL", "https://prod-api.nessieisreal.com").rstrip("/")
    if not base.startswith("https://") or not os.getenv("NESSIE_API_KEY"):
        parser.error("Configure HTTPS Nessie endpoint and private API key first")
    try:
        with httpx.Client(timeout=15) as client:
            for account_id in accounts.values():
                response = client.get(base + "/accounts/" + account_id,
                                      params={"key": os.environ["NESSIE_API_KEY"]})
                response.raise_for_status()
                record = response.json()
                if record.get("_id") != account_id or record.get("customer_id") != customer:
                    parser.error("Nessie account ownership mismatch; nothing linked")
    except (httpx.HTTPError, ValueError):
        parser.error("Unable to verify Nessie ownership; nothing linked")
    store = NessieLinkStore(os.getenv("TIGERDATA_DATABASE_URL", ""))
    store.initialize()
    store.link(args.subject, customer, accounts)
    print(f"Linked Auth0 user to Nessie customer at slot {args.slot} ({len(accounts)} account(s)).")


if __name__ == "__main__":
    main()
