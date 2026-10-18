#!/usr/bin/env python3
"""Safely copy existing local SQLite joint membership/payment rows to TigerData.

Usage from project root:
  py backend/scripts/migrate_joint_to_tigerdata.py           # read-only preview
  py backend/scripts/migrate_joint_to_tigerdata.py --apply   # atomic migration

Does not delete SQLite rows or change backend configuration. Never migrate
payments to a different shared Nessie sandbox; verify target database first.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3
import sys

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from dotenv import load_dotenv
from nessie_links import NessieLinkStore
from joint_pg import JointPostgres


def timestamp(value: str) -> datetime:
    parsed = datetime.fromisoformat(value)
    return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed


def read_rows(path: Path):
    if not path.is_file():
        raise ValueError("SQLite file does not exist; nothing to migrate.")
    with sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True) as conn:
        conn.row_factory = sqlite3.Row
        present = {
            row[0] for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        if not {"joint_accounts", "joint_payments"} <= present:
            raise ValueError("SQLite joint_accounts/joint_payments tables are missing.")
        accounts = [dict(r) for r in conn.execute(
            "SELECT account_id,name,threshold_cents,primary_sub,dependent_sub,recipients "
            "FROM joint_accounts")]
        payments = [dict(r) for r in conn.execute(
            "SELECT id,account_id,initiator,primary_sub,status,amount_cents,"
            "recipient,reason,assessment,decision_by,nessie_id,created_at "
            "FROM joint_payments")]
    return accounts, payments


def migration_values(accounts, payments):
    transformed_accounts = []
    for row in accounts:
        values = {
            **row,
            "primary_sub": NessieLinkStore.key(row["primary_sub"]),
            "dependent_sub": NessieLinkStore.key(row["dependent_sub"]),
        }
        json.loads(values["recipients"])
        transformed_accounts.append(values)
    transformed_payments = []
    for row in payments:
        values = {
            **row,
            "initiator": NessieLinkStore.key(row["initiator"]),
            "primary_sub": NessieLinkStore.key(row["primary_sub"]),
            "decision_by": (
                NessieLinkStore.key(row["decision_by"])
                if row["decision_by"] else None
            ),
            "created_at": timestamp(row["created_at"]),
        }
        json.loads(values["recipient"])
        json.loads(values["assessment"])
        transformed_payments.append(values)
    return transformed_accounts, transformed_payments


def apply(joint: JointPostgres, accounts, payments):
    joint.initialize()
    with joint.store.connect() as conn:
        # Single transaction for all rows; serialize with other administration.
        conn.execute("SELECT pg_advisory_xact_lock(50315892)")
        for row in accounts:
            conn.execute(
                """INSERT INTO cp_joint_accounts
                   (account_id,name,threshold_cents,primary_sub,dependent_sub,recipients)
                   VALUES(%s,%s,%s,%s,%s,%s)
                   ON CONFLICT(account_id) DO NOTHING""",
                tuple(row[k] for k in (
                    "account_id", "name", "threshold_cents",
                    "primary_sub", "dependent_sub", "recipients"
                )))
            found = conn.execute(
                """SELECT name,threshold_cents,primary_sub,dependent_sub,recipients
                   FROM cp_joint_accounts WHERE account_id=%s""",
                (row["account_id"],)).fetchone()
            if (not found or tuple(found[:4]) != tuple(row[k] for k in (
                "name","threshold_cents","primary_sub","dependent_sub"
            )) or json.loads(found[4]) != json.loads(row["recipients"])):
                raise ValueError("Existing joint account differs. No rows copied; manual review needed.")
        for row in payments:
            conn.execute(
                """INSERT INTO cp_joint_payments
                   (id,account_id,initiator,primary_sub,status,amount_cents,
                    recipient,reason,assessment,decision_by,nessie_id,created_at)
                   VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                   ON CONFLICT(id) DO NOTHING""",
                tuple(row[k] for k in (
                    "id", "account_id", "initiator", "primary_sub", "status",
                    "amount_cents", "recipient", "reason", "assessment",
                    "decision_by", "nessie_id", "created_at"
                )))
            found = conn.execute(
                """SELECT account_id,initiator,primary_sub,status,amount_cents,
                          recipient,reason,assessment,decision_by,nessie_id
                   FROM cp_joint_payments WHERE id=%s""",
                (row["id"],)).fetchone()
            fields = ("account_id","initiator","primary_sub","status",
                      "amount_cents","recipient","reason","assessment",
                      "decision_by","nessie_id")
            if (not found or any(
                (json.loads(actual) != json.loads(row[field])
                 if field in ("recipient","assessment") else actual != row[field])
                for actual, field in zip(found, fields)
            )):
                raise ValueError("Existing payment differs. No rows copied; manual review needed.")
        # Commit only when all records match; failures roll everything back.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    load_dotenv(BACKEND / ".env")
    db_path = Path(os.getenv("DB_PATH", str(BACKEND / "creditpilot.sqlite3"))).resolve()
    accounts, payments = migration_values(*read_rows(db_path))
    print(f"Local SQLite joint accounts: {len(accounts)}; payment requests: {len(payments)}")
    if not args.apply:
        print("DRY RUN: no data changed. Add --apply to copy existing rows.")
        return
    url = os.getenv("TIGERDATA_DATABASE_URL", "").strip()
    if not url:
        raise ValueError("TIGERDATA_DATABASE_URL missing in backend/.env.")
    apply(JointPostgres(url), accounts, payments)
    print("SUCCESS: Joint data safely copied to TigerData. SQLite remains unchanged.")
    print("Verify tables in the chosen TigerData service before switching JOINT_STORE=tigerdata.")


if __name__ == "__main__":
    try:
        main()
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception:
        # psycopg errors can contain connection URIs; never print raw exceptions.
        print("ERROR: Migration failed or was rolled back. Verify DB and permissions.", file=sys.stderr)
        sys.exit(1)
