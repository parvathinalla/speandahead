"""Server-side Auth0 identity -> Nessie customer/account mapping in TigerData."""
import hashlib
import json

from tigerdata_store import TigerDataStore


class NessieLinkStore:
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

    @staticmethod
    def key(auth0_sub: str) -> str:
        if not auth0_sub or len(auth0_sub) > 256 or auth0_sub.startswith("demo-"):
            raise ValueError("A verified Auth0 subject is required")
        return hashlib.sha256(auth0_sub.encode("utf-8")).hexdigest()

    def get(self, auth0_sub: str):
        with self.store.connect() as conn:
            row = conn.execute(
                "SELECT customer_id, accounts FROM cp_nessie_links WHERE owner_key=%s",
                (self.key(auth0_sub),),
            ).fetchone()
        if not row:
            return None
        accounts = row[1] if isinstance(row[1], dict) else json.loads(row[1])
        return {"customer_id": row[0], "accounts": accounts}

    def link(self, auth0_sub: str, customer_id: str, accounts: dict):
        """Admin-only offline provisioning; never allow users to choose an account."""
        if not customer_id or not accounts.get("checking"):
            raise ValueError("Nessie customer and checking account IDs are required")
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
