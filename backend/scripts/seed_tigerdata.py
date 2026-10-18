#!/usr/bin/env python3
"""Seed CreditPilot's 500 fictional portfolios into your private TigerData database.

From repository root:
    python backend/scripts/seed_tigerdata.py          # preview, no connection
    python backend/scripts/seed_tigerdata.py --apply  # create schema and profiles
    python backend/scripts/seed_tigerdata.py --verify # read counts only

Never commit backend/.env or your TigerData connection string.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from dotenv import load_dotenv
from synthetic_bank import CATALOG_SIZE
from tigerdata_store import TigerDataStore


def run() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Insert 500 profiles without overwriting existing ones")
    mode.add_argument("--verify", action="store_true", help="Check existing profile counts")
    args = parser.parse_args()

    if not args.apply and not args.verify:
        print(f"DRY RUN: would create {CATALOG_SIZE} fictional customer portfolios in TigerData.")
        print("Each portfolio contains checking/savings/card accounts, upcoming bills and transaction history.")
        print("Nothing has been inserted. Run again with --apply to proceed.")
        return

    load_dotenv(BACKEND / ".env", override=False)
    dsn = os.getenv("TIGERDATA_DATABASE_URL", "").strip()
    if not dsn:
        raise ValueError("Set TIGERDATA_DATABASE_URL in backend/.env first (do not share or commit it).")
    store = TigerDataStore(dsn)
    if args.apply:
        store.initialize()  # safe to rerun; existing portfolios and claims remain untouched
    stats = store.stats()
    print(f"TigerData profiles: {stats['profiles_total']}/{CATALOG_SIZE}")
    print(f"Claimed by Auth0 logins: {stats['profiles_claimed']}")
    print(f"Available for first login: {stats['profiles_available']}")
    print("Synthetic transaction rows are materialized when each verified Auth0 user claims a profile.")
    if args.apply:
        print("SUCCESS: profile catalog initialized. No real bank transactions occurred.")


if __name__ == "__main__":
    try:
        run()
    except (ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception:
        # PostgreSQL errors may embed credentials in connection details.
        print("ERROR: TigerData operation failed. Check credentials, TimescaleDB support and schema permissions.", file=sys.stderr)
        sys.exit(1)
