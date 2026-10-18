-- CreditPilot / TigerData schema v1. Run only with your own dedicated service DB.
-- Ordinary relational tables: tenant portfolio assignment and transfer idempotency.
-- Time-series hypertable: signed-in user's synthetic transaction history.
-- Do not store Auth0 passwords, emails, tokens, or real bank credentials here.

CREATE TABLE IF NOT EXISTS cp_demo_profiles (
    slot INTEGER PRIMARY KEY,
    owner_sub TEXT UNIQUE,
    payload JSONB NOT NULL,
    assigned_at TIMESTAMPTZ,
    CONSTRAINT cp_demo_valid_slot CHECK (slot BETWEEN 0 AND 499)
);

CREATE INDEX IF NOT EXISTS cp_demo_profiles_owner_idx
    ON cp_demo_profiles(owner_sub) WHERE owner_sub IS NOT NULL;

CREATE TABLE IF NOT EXISTS cp_demo_transfers (
    request_key TEXT PRIMARY KEY,
    owner_sub TEXT NOT NULL,
    amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    status TEXT NOT NULL DEFAULT 'simulated_posted',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cp_demo_transfers_owner_idx
    ON cp_demo_transfers(owner_sub, created_at DESC);

CREATE TABLE IF NOT EXISTS cp_demo_transactions (
    occurred_at TIMESTAMPTZ NOT NULL,
    transaction_id TEXT NOT NULL,
    owner_sub TEXT NOT NULL,
    profile_id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    account_kind TEXT NOT NULL,
    merchant TEXT NOT NULL,
    category TEXT NOT NULL,
    direction TEXT NOT NULL CHECK (direction IN ('debit', 'credit')),
    amount NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
    PRIMARY KEY (occurred_at, transaction_id)
);

-- TimescaleDB is required in the TigerData service; this is idempotent.
-- Legacy syntax is supported alongside the newer CREATE TABLE ... WITH (tsdb.hypertable).
SELECT create_hypertable(
    'cp_demo_transactions',
    by_range('occurred_at'),
    if_not_exists => TRUE
);

CREATE INDEX IF NOT EXISTS cp_demo_transactions_owner_time_idx
    ON cp_demo_transactions(owner_sub, occurred_at DESC);
