"""TigerData / TimescaleDB production-oriented synthetic portfolio repository.

The verified Auth0 subject is the ONLY caller-supplied tenant identifier.
PostgreSQL stores immutable 500 demo slots, mutable per-owner portfolio JSONB,
idempotent simulated transfers and normalized transactions in a hypertable.

Never store passwords, identity tokens, user email, or real banking credentials.
This module does not perform bank transfers.
"""
from __future__ import annotations

from datetime import date, datetime, time, timezone
from decimal import Decimal
import hashlib
import json
from pathlib import Path
from typing import Any, Callable, Optional

import synthetic_bank as dataset

SCHEMA_PATH = Path(__file__).resolve().parent / "sql" / "tigerdata.sql"


def validate_connection_url(dsn: str) -> str:
    """Reject DSNs without TLS. Do not print the supplied secret URL."""
    if not dsn or not dsn.startswith(("postgresql://", "postgres://")):
        raise ValueError("TIGERDATA_DATABASE_URL must be a PostgreSQL connection URL")
    # psycopg conninfo parser safely understands percent-encoded usernames/passwords.
    try:
        from psycopg.conninfo import conninfo_to_dict
        values = conninfo_to_dict(dsn)
    except Exception:
        raise ValueError("Invalid TigerData connection URL") from None
    if values.get("sslmode", "verify-full") not in ("require", "verify-ca", "verify-full"):
        raise ValueError("TigerData connections require sslmode=require or stronger")
    if not values.get("host") or not values.get("dbname"):
        raise ValueError("TigerData connection URL requires host and database name")
    return dsn


def _timestamp(value: str) -> datetime:
    when = date.fromisoformat(value[:10])
    return datetime.combine(when, time(hour=12), tzinfo=timezone.utc)


class TigerDataStore:
    def __init__(self, connection_url: str):
        self.url = validate_connection_url(connection_url)
        try:
            import psycopg
            from psycopg.types.json import Jsonb
        except ImportError:
            raise RuntimeError(
                "TigerData requires psycopg: pip install 'psycopg[binary]>=3.2,<4'"
            ) from None
        self.driver = psycopg
        self.Jsonb = Jsonb

    def connect(self):
        # Default verify-full if URL omits sslmode. Never downgrade an
        # explicitly configured verify-ca/verify-full policy.
        options = {"connect_timeout": 8,
                   "application_name": "creditpilot-demo-sdk"}
        from psycopg.conninfo import conninfo_to_dict
        if not conninfo_to_dict(self.url).get("sslmode"):
            options["sslmode"] = "verify-full"
        try:
            return self.driver.connect(self.url, **options)
        except self.driver.Error:
            # psycopg connection exceptions may include the original DSN.
            raise RuntimeError("TigerData connection failed. Verify private "
                               "credentials, network access, and TLS.") from None

    def initialize(self, count: int = dataset.CATALOG_SIZE) -> None:
        if count != dataset.CATALOG_SIZE:
            raise ValueError("The public TigerData catalog uses exactly 500 slots")
        schema = SCHEMA_PATH.read_text(encoding="utf8")
        # This trusted server-owned SQL file has no untrusted interpolated inputs.
        # Strip comment lines before splitting SQL statements.
        no_comments = "\n".join(line for line in schema.splitlines()
                                if not line.lstrip().startswith("--"))
        commands = [cmd.strip() for cmd in no_comments.split(";") if cmd.strip()]
        with self.connect() as conn:
            for statement in commands:
                conn.execute(statement)
            # An existing assignment can NEVER be overwritten by an app restart.
            existing = conn.execute(
                "SELECT COUNT(*) FROM cp_demo_profiles").fetchone()[0]
            if existing < count:
                existing_slots = {
                    row[0] for row in conn.execute(
                        "SELECT slot FROM cp_demo_profiles").fetchall()
                }
                rows = [
                    (slot, self.Jsonb(dataset._make_profile(slot, date.today())))
                    for slot in range(count) if slot not in existing_slots
                ]
                with conn.cursor() as cur:
                    cur.executemany(
                        "INSERT INTO cp_demo_profiles(slot,payload) VALUES(%s,%s) "
                        "ON CONFLICT(slot) DO NOTHING", rows)

    @staticmethod
    def _subject(subject: str) -> None:
        if not subject or subject.startswith("demo-") or len(subject) > 256:
            raise ValueError("Verified Auth0 subject is required")

    def _lock_user(self, conn, subject: str) -> None:
        # Serialize two concurrent first-logins of the SAME Auth0 subject.
        # Hash collisions merely serialize unrelated users, not mix their data.
        conn.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (subject,))

    @staticmethod
    def _decode(row) -> dict:
        data = row[0]
        return data if isinstance(data, dict) else json.loads(data)

    def _write_transactions(self, conn, subject: str, profile: dict,
                            records: list[dict]) -> None:
        parameters = [
            (
                _timestamp(row["date"]), row["id"], subject,
                profile["portfolio_id"], row["account_id"], row["account_kind"],
                row["merchant"], row["category"], row["direction"],
                Decimal(str(row["amount"])),
            )
            for row in records
        ]
        if parameters:
            with conn.cursor() as cursor:
                cursor.executemany(
                    """INSERT INTO cp_demo_transactions(
                        occurred_at, transaction_id, owner_sub, profile_id,
                        account_id, account_kind, merchant, category,
                        direction, amount
                    ) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    ON CONFLICT(occurred_at,transaction_id) DO NOTHING""",
                    parameters)

    def get_or_claim(self, subject: str) -> dict:
        self._subject(subject)
        with self.connect() as conn:
            self._lock_user(conn, subject)
            row = conn.execute(
                "SELECT payload FROM cp_demo_profiles WHERE owner_sub=%s",
                (subject,)).fetchone()
            if row:
                return self._decode(row)
            start = int.from_bytes(
                hashlib.sha256(subject.encode("utf8")).digest()[:8], "big"
            ) % dataset.CATALOG_SIZE
            # Row-level lock ensures two different users cannot claim same slot.
            row = conn.execute(
                "SELECT slot,payload FROM cp_demo_profiles "
                "WHERE owner_sub IS NULL AND slot >= %s ORDER BY slot "
                "FOR UPDATE SKIP LOCKED LIMIT 1", (start,)
            ).fetchone()
            if row is None:
                row = conn.execute(
                    "SELECT slot,payload FROM cp_demo_profiles "
                    "WHERE owner_sub IS NULL ORDER BY slot "
                    "FOR UPDATE SKIP LOCKED LIMIT 1"
                ).fetchone()
            if row is None:
                raise RuntimeError("No unassigned TigerData demo profiles available")
            slot, raw = row
            profile = raw if isinstance(raw, dict) else json.loads(raw)
            claimed = conn.execute(
                """UPDATE cp_demo_profiles
                   SET owner_sub=%s, assigned_at=now()
                   WHERE slot=%s AND owner_sub IS NULL RETURNING slot""",
                (subject, slot),
            ).fetchone()
            if claimed is None:
                raise RuntimeError("Concurrent demo profile claim failed; retry login")
            self._write_transactions(conn, subject, profile,
                                     profile.get("transactions", []))
            return profile

    def get(self, subject: str) -> Optional[dict]:
        self._subject(subject)
        with self.connect() as conn:
            row = conn.execute(
                "SELECT payload FROM cp_demo_profiles WHERE owner_sub=%s",
                (subject,)).fetchone()
            return self._decode(row) if row else None

    def stats(self) -> dict:
        with self.connect() as conn:
            total, claimed = conn.execute(
                "SELECT COUNT(*), COUNT(owner_sub) FROM cp_demo_profiles"
            ).fetchone()
            return {"profiles_total": total, "profiles_claimed": claimed,
                    "profiles_available": total - claimed,
                    "source": dataset.DATA_SOURCE, "storage": "tigerdata"}

    def _update(self, subject: str, operation: Callable[[dict], Any]) -> Any:
        self._subject(subject)
        with self.connect() as conn:
            self._lock_user(conn, subject)
            row = conn.execute(
                "SELECT slot,payload FROM cp_demo_profiles "
                "WHERE owner_sub=%s FOR UPDATE", (subject,)
            ).fetchone()
            if row is None:
                raise ValueError("No banking portfolio assigned to this Auth0 user")
            profile = row[1] if isinstance(row[1], dict) else json.loads(row[1])
            result = operation(profile)
            conn.execute(
                "UPDATE cp_demo_profiles SET payload=%s WHERE slot=%s AND owner_sub=%s",
                (self.Jsonb(profile), row[0], subject),
            )
            return result

    def upsert_bill(self, subject: str, values: dict,
                    bill_id: Optional[str] = None) -> dict:
        def operation(profile):
            bills = profile["app_bills"]
            if bill_id and bill_id not in bills:
                raise ValueError("Bill does not belong to authenticated user")
            ident = bill_id or (
                profile["portfolio_id"] + "-bill-custom-" + str(len(bills) + 1))
            while not bill_id and ident in bills:
                ident += "x"
            due = date.fromisoformat(values["payment_date"])
            result = {
                **bills.get(ident, {}),
                "bill_id": ident,
                "payee": values["payee"],
                "nickname": values["payee"],
                "payment_amount": dataset._dollars(values["payment_amount"]),
                "payment_date": due.isoformat(),
                "upcoming_payment_date": due.isoformat(),
                "recurring_date": due.day,
                "category": values["category"],
                "frequency": values["frequency"],
                "status": "pending",
                "account_id": profile["ids"]["accounts"]["checking"],
                "source": dataset.DATA_SOURCE,
            }
            bills[ident] = result
            return result
        return self._update(subject, operation)

    def delete_bill(self, subject: str, bill_id: str) -> bool:
        def operation(profile):
            if bill_id not in profile["app_bills"]:
                raise ValueError("Bill does not belong to authenticated user")
            del profile["app_bills"][bill_id]
            return True
        return self._update(subject, operation)

    def revise_income(self, subject: str, income: float) -> dict:
        def operation(profile):
            profile["monthly_income"] = dataset._dollars(income)
            return {"monthly_income": profile["monthly_income"],
                    "source": dataset.DATA_SOURCE}
        return self._update(subject, operation)

    def simulated_transfer(self, subject: str, amount: float,
                           key: str, savings_reserve: float) -> dict:
        value = Decimal(str(amount)).quantize(Decimal("0.01"))
        reserve = Decimal(str(savings_reserve)).quantize(Decimal("0.01"))
        if value <= 0 or reserve < 0 or len(key) < 8:
            raise ValueError("Invalid transfer amount, reserve or idempotency key")
        with self.connect() as conn:
            self._lock_user(conn, subject)
            prior = conn.execute(
                "SELECT owner_sub,amount,status FROM cp_demo_transfers "
                "WHERE request_key=%s FOR UPDATE", (key,)
            ).fetchone()
            row = conn.execute(
                "SELECT slot,payload FROM cp_demo_profiles "
                "WHERE owner_sub=%s FOR UPDATE", (subject,)
            ).fetchone()
            if not row:
                raise ValueError("No demo portfolio assigned")
            profile = row[1] if isinstance(row[1], dict) else json.loads(row[1])
            balances = profile["accounts"]
            if prior:
                if prior[0] != subject or Decimal(prior[1]) != value:
                    raise ValueError("Idempotency key already assigned to another request")
                return {
                    "idempotency_key": key, "status": prior[2],
                    "previous_request": True, "simulation": True,
                    "balances": {
                        "checking": balances["checking"]["balance"],
                        "savings": balances["savings"]["balance"],
                    },
                }
            savings = Decimal(str(balances["savings"]["balance"]))
            checking = Decimal(str(balances["checking"]["balance"]))
            if savings - value < reserve:
                raise ValueError("Transfer would violate protected savings reserve")
            balances["savings"]["balance"] = dataset._dollars(savings - value)
            balances["checking"]["balance"] = dataset._dollars(checking + value)
            today = date.today().isoformat()
            new_entries = [
                {
                    "id": "transfer-" + key + "-" + account,
                    "account_id": profile["ids"]["accounts"][account],
                    "account_kind": account, "merchant": "Own account transfer",
                    "category": "transfer", "direction": direction,
                    "amount": dataset._dollars(value), "date": today,
                    "status": "posted", "source": dataset.DATA_SOURCE,
                }
                for account, direction in (("savings", "debit"), ("checking", "credit"))
            ]
            profile["transactions"] = new_entries + profile["transactions"]
            conn.execute(
                "UPDATE cp_demo_profiles SET payload=%s WHERE slot=%s AND owner_sub=%s",
                (self.Jsonb(profile), row[0], subject))
            self._write_transactions(conn, subject, profile, new_entries)
            conn.execute(
                "INSERT INTO cp_demo_transfers(request_key,owner_sub,amount) "
                "VALUES(%s,%s,%s)", (key, subject, value))
            return {
                "idempotency_key": key, "status": "simulated_posted",
                "previous_request": False, "simulation": True,
                "balances": {
                    "checking": balances["checking"]["balance"],
                    "savings": balances["savings"]["balance"],
                },
            }

    def transactions(self, subject: str, limit=50, offset=0) -> dict:
        self._subject(subject)
        if not 1 <= limit <= 100 or offset < 0:
            raise ValueError("Invalid pagination")
        with self.connect() as conn:
            total = conn.execute(
                "SELECT COUNT(*) FROM cp_demo_transactions WHERE owner_sub=%s",
                (subject,)).fetchone()[0]
            rows = conn.execute(
                """SELECT transaction_id, account_id, account_kind, merchant,
                          category, direction, amount, occurred_at
                   FROM cp_demo_transactions WHERE owner_sub=%s
                   ORDER BY occurred_at DESC, transaction_id DESC
                   LIMIT %s OFFSET %s""", (subject, limit, offset)
            ).fetchall()
        return {
            "transactions": [
                {
                    "id": r[0], "account_id": r[1], "account_kind": r[2],
                    "merchant": r[3], "category": r[4], "direction": r[5],
                    "amount": float(r[6]), "date": r[7].date().isoformat(),
                    "status": "posted", "source": dataset.DATA_SOURCE,
                }
                for r in rows
            ],
            "total": total, "limit": limit, "offset": offset,
            "source": dataset.DATA_SOURCE,
            "storage": "tigerdata",
        }

    def spending_summary(self, subject: str, days: int = 30) -> dict:
        self._subject(subject)
        if not 1 <= days <= 365:
            raise ValueError("Days must be between 1 and 365")
        with self.connect() as conn:
            rows = conn.execute(
                """SELECT category, SUM(amount) AS total, COUNT(*) AS count
                   FROM cp_demo_transactions
                   WHERE owner_sub=%s
                     AND occurred_at >= now() - (%s * interval '1 day')
                     AND direction='debit' AND category <> 'transfer'
                   GROUP BY category ORDER BY total DESC""",
                (subject, days)
            ).fetchall()
        return {
            "period_days": days, "by_category": [
                {"category": r[0], "amount": float(r[1]), "count": r[2]}
                for r in rows
            ], "source": dataset.DATA_SOURCE,
            "storage": "tigerdata",
        }
