"""PostgreSQL-backed joint approvals for Nessie-mode CreditPilot.

A narrow DB adapter preserves the existing joint router contracts while replacing
SQLite-only syntax. Every PG joint actor identifier is SHA-256 of the verified
Auth0 subject, consistent with cp_nessie_links. Do not use in demo-auth mode.
"""
from __future__ import annotations

from pathlib import Path
import re

from psycopg.rows import dict_row

from nessie_links import NessieLinkStore
from tigerdata_store import TigerDataStore

_SCHEMA = Path(__file__).resolve().parent / "sql" / "nessie_joint_tigerdata.sql"


class JointPostgresConnection:
    is_joint_postgres = True

    def __init__(self, raw):
        self.raw = raw
        self.in_transaction = False

    @staticmethod
    def identity(verified_sub: str) -> str:
        return NessieLinkStore.key(verified_sub)

    def execute(self, sql: str, params=()):
        query = sql.strip()
        if query.upper() == "BEGIN IMMEDIATE":
            if self.in_transaction:
                raise RuntimeError("Nested joint transaction")
            self.raw.execute("BEGIN")
            # Serialize joint state transitions and admin provisioning across
            # API instances. Small hackathon workload; prioritize correctness.
            self.raw.execute("SELECT pg_advisory_xact_lock(50315892)")
            self.in_transaction = True
            return None
        # Only trusted SQL shipped with joint_accounts.py or the operator script
        # is accepted by this adapter. SQL values are always bound parameters.
        query = re.sub(r"\bjoint_accounts\b", "cp_joint_accounts", query)
        query = re.sub(r"\bjoint_payments\b", "cp_joint_payments", query)
        query = query.replace("rowid DESC", "id DESC").replace("?", "%s")
        # Serializes concurrent sends on one shared joint account. Every execution
        # locks this row before checking pending reservations and marking processing.
        if self.in_transaction and (
            "FROM cp_joint_accounts WHERE" in query and
            "FOR UPDATE" not in query.upper()
        ):
            query += " FOR UPDATE"
        return self.raw.execute(query, params)

    def commit(self):
        if self.in_transaction:
            self.raw.execute("COMMIT")
            self.in_transaction = False

    def close(self):
        try:
            if self.in_transaction:
                self.raw.execute("ROLLBACK")
        finally:
            self.raw.close()


class JointPostgres:
    def __init__(self, dsn: str):
        self.store = TigerDataStore(dsn)

    def initialize(self) -> None:
        NessieLinkStore(self.store.url).initialize()
        ddl = _SCHEMA.read_text(encoding="utf-8")
        ddl = "\n".join(
            line for line in ddl.splitlines()
            if not line.lstrip().startswith("--")
        )
        statements = [part.strip() for part in ddl.split(";") if part.strip()]
        with self.store.connect() as conn:
            for statement in statements:
                conn.execute(statement)

    def connect(self) -> JointPostgresConnection:
        raw = self.store.connect()
        raw.row_factory = dict_row
        raw.autocommit = True
        return JointPostgresConnection(raw)
