"""Offline tests: TigerData joint SQL adapter, hashed Auth0 IDs, migration safety."""
import hashlib

from joint_pg import JointPostgresConnection
from scripts.link_joint_account import provision
from scripts.migrate_joint_to_tigerdata import migration_values

PRIMARY = "auth0|primary"
DEPENDENT = "auth0|dependent"
ACCOUNT = "a" * 24
RECIPIENT = {"id": "merchant", "name": "Fictional payee", "account_id": "b" * 24}


class Cursor:
    def fetchone(self):
        return None


class FakeRawPostgres:
    def __init__(self):
        self.queries = []
        self.closed = False

    def execute(self, sql, params=()):
        self.queries.append((sql, params))
        return Cursor()

    def close(self):
        self.closed = True


def test_admin_provisioning_hashes_auth0_subjects_before_postgres_insert():
    raw = FakeRawPostgres()
    conn = JointPostgresConnection(raw)
    provision(conn, ACCOUNT, PRIMARY, DEPENDENT, "Joint", [RECIPIENT])
    inserted = next(params for sql, params in raw.queries if
                    "INSERT INTO cp_joint_accounts" in sql)
    assert inserted[2] == hashlib.sha256(PRIMARY.encode()).hexdigest()
    assert inserted[3] == hashlib.sha256(DEPENDENT.encode()).hexdigest()
    all_bound_values = str([params for _, params in raw.queries])
    assert PRIMARY not in all_bound_values and DEPENDENT not in all_bound_values
    assert any("pg_advisory_xact_lock" in sql for sql, _ in raw.queries)
    assert any(sql == "COMMIT" for sql, _ in raw.queries)
    conn.close()


def test_joint_adapter_rewrites_sqlite_only_syntax_and_locks_joint_row():
    raw = FakeRawPostgres()
    conn = JointPostgresConnection(raw)
    conn.execute("BEGIN IMMEDIATE")
    conn.execute("SELECT * FROM joint_accounts WHERE primary_sub=? OR dependent_sub=?",
                 ("one", "two"))
    query, params = raw.queries[-1]
    assert "FROM cp_joint_accounts" in query
    assert "primary_sub=%s OR dependent_sub=%s" in query
    assert "FOR UPDATE" in query
    assert params == ("one", "two")
    conn.execute("SELECT * FROM joint_payments ORDER BY created_at DESC, rowid DESC")
    assert "cp_joint_payments" in raw.queries[-1][0]
    assert "id DESC" in raw.queries[-1][0]
    assert "rowid" not in raw.queries[-1][0]
    conn.close()
    assert any(sql == "ROLLBACK" for sql, _ in raw.queries)
    assert raw.closed


def test_sqlite_migration_rekeys_all_membership_and_payment_actor_ids():
    accounts = [{
        "account_id": ACCOUNT, "name": "Joint", "threshold_cents": 2000,
        "primary_sub": PRIMARY, "dependent_sub": DEPENDENT,
        "recipients": '[{"id":"merchant","name":"Fictional payee","account_id":"' + "b" * 24 + '"}]'
    }]
    payments = [{
        "id": "test-request", "account_id": ACCOUNT,
        "initiator": DEPENDENT, "primary_sub": PRIMARY,
        "status": "approved", "amount_cents": 100,
        "recipient": '{"id":"merchant","name":"Fictional payee"}',
        "reason": "Review", "assessment": '{"suspicious":false}',
        "decision_by": PRIMARY, "nessie_id": None,
        "created_at": "2026-10-18 12:30:00"
    }]
    converted_accounts, converted_payments = migration_values(accounts, payments)
    assert converted_accounts[0]["primary_sub"] == hashlib.sha256(PRIMARY.encode()).hexdigest()
    assert converted_accounts[0]["dependent_sub"] == hashlib.sha256(DEPENDENT.encode()).hexdigest()
    assert converted_payments[0]["initiator"] == converted_accounts[0]["dependent_sub"]
    assert converted_payments[0]["primary_sub"] == converted_accounts[0]["primary_sub"]
    assert converted_payments[0]["decision_by"] == converted_accounts[0]["primary_sub"]
    assert converted_payments[0]["created_at"].tzinfo is not None
