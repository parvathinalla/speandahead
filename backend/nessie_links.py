"""Server-side Auth0 identity -> Nessie customer/account mapping in TigerData."""
import hashlib
import json
import re

from tigerdata_store import TigerDataStore


class NessieLinkStore:
    @staticmethod
    def validate_mapping(customer_id, accounts):
        valid_id = lambda value: isinstance(value, str) and re.fullmatch(
            r"(?:[0-9a-fA-F]{24}|[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})", value)
        if (not valid_id(customer_id) or not isinstance(accounts, dict)
                or not accounts.get("checking") or not all(valid_id(value) for value in accounts.values())
                or len(set(accounts.values())) != len(accounts)):
            raise ValueError("Invalid Nessie customer/account mapping; administrator review required")

    def __init__(self, url: str):
        self.store = TigerDataStore(url)

    def initialize(self):
        with self.store.connect() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS cp_nessie_links (
                    owner_key TEXT PRIMARY KEY,
                    customer_id TEXT NOT NULL UNIQUE,
                    accounts JSONB NOT NULL
                )
            """)
            # Console imports can create a nullable JSON table without keys.
            # Upgrade in one transaction; duplicate/invalid rows abort without
            # deleting or overwriting operator data.
            conn.execute("LOCK TABLE public.cp_nessie_links IN ACCESS EXCLUSIVE MODE")
            conn.execute("ALTER TABLE public.cp_nessie_links ADD COLUMN IF NOT EXISTS scenario JSONB DEFAULT '{}'::jsonb")
            conn.execute("ALTER TABLE public.cp_nessie_links ALTER COLUMN accounts TYPE JSONB USING accounts::jsonb")
            for column in ("owner_key", "customer_id", "accounts"):
                conn.execute("ALTER TABLE public.cp_nessie_links ALTER COLUMN " + column + " SET NOT NULL")
            primary = conn.execute("SELECT 1 FROM information_schema.table_constraints WHERE table_schema='public' AND table_name='cp_nessie_links' AND constraint_type='PRIMARY KEY'").fetchone()
            if not primary:
                conn.execute("ALTER TABLE public.cp_nessie_links ADD PRIMARY KEY (owner_key)")
            conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS cp_nessie_links_customer_unique ON public.cp_nessie_links(customer_id)")
            shape = conn.execute("SELECT 1 FROM pg_constraint WHERE conrelid='public.cp_nessie_links'::regclass AND conname='cp_nessie_links_shape'").fetchone()
            if not shape:
                conn.execute("""ALTER TABLE public.cp_nessie_links ADD CONSTRAINT cp_nessie_links_shape CHECK (
                    owner_key ~ '^[0-9a-f]{64}$' AND jsonb_typeof(accounts)='object'
                    AND accounts ? 'checking' AND jsonb_typeof(accounts->'checking')='string'
                    AND length(accounts->>'checking') > 0)""")

    @staticmethod
    def key(auth0_sub: str) -> str:
        if not auth0_sub or len(auth0_sub) > 256 or auth0_sub.startswith("demo-"):
            raise ValueError("A verified Auth0 subject is required")
        return hashlib.sha256(auth0_sub.encode("utf-8")).hexdigest()

    def get(self, auth0_sub: str):
        with self.store.connect() as conn:
            row = conn.execute(
                "SELECT customer_id, accounts, scenario FROM cp_nessie_links WHERE owner_key=%s",
                (self.key(auth0_sub),),
            ).fetchone()
        if not row:
            return None
        accounts = row[1] if isinstance(row[1], dict) else json.loads(row[1])
        self.validate_mapping(row[0], accounts)
        scenario = row[2] or {}
        if not isinstance(scenario, dict) or any(
                not isinstance(scenario.get(field, {}), dict)
                for field in ("app_bills", "app_scenario")):
            raise ValueError("Invalid Nessie scenario metadata; administrator review required")
        # Legacy seed scenarios included another customer's checking account.
        # Keep the operator's original JSON intact, but never expose that payee
        # as an authenticated user's own bank account. Joint access is governed
        # separately by admin-provisioned memberships.
        own_accounts = {name: ident for name, ident in accounts.items()
                        if name != "partner_checking"}
        return {"customer_id": row[0], "accounts": own_accounts, "scenario": scenario}

    def link(self, auth0_sub: str, customer_id: str, accounts: dict):
        """Admin-only offline provisioning; never allow users to choose an account."""
        self.validate_mapping(customer_id, accounts)
        owner_key = self.key(auth0_sub)
        with self.store.connect() as conn:
            conn.execute(
                """INSERT INTO cp_nessie_links(owner_key, customer_id, accounts)
                   VALUES (%s, %s, %s) ON CONFLICT (owner_key) DO NOTHING""",
                (owner_key, customer_id, self.store.Jsonb(accounts)),
            )
            row = conn.execute(
                "SELECT customer_id, accounts FROM cp_nessie_links WHERE owner_key=%s",
                (owner_key,),
            ).fetchone()
            saved = row[1] if isinstance(row[1], dict) else json.loads(row[1])
            if row[0] != customer_id or saved != accounts:
                raise ValueError("This Auth0 user is already linked to a different Nessie account")
