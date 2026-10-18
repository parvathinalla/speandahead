-- CreditPilot / TigerData schema for Nessie-backed Auth0 users.
-- Run in the selected, dedicated TigerData service SQL Editor.
-- This stores only references/permissions. Account balances stay in Nessie.
-- No secrets, OAuth tokens, passwords, or real banking data belong here.

CREATE TABLE IF NOT EXISTS cp_nessie_links (
    owner_key TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL UNIQUE,
    accounts JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS cp_joint_accounts (
    account_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    threshold_cents BIGINT CHECK (threshold_cents IS NULL OR threshold_cents >= 0),
    primary_sub TEXT NOT NULL UNIQUE,
    dependent_sub TEXT NOT NULL UNIQUE,
    recipients TEXT NOT NULL,
    CHECK (primary_sub <> dependent_sub)
);
-- primary_sub and dependent_sub contain SHA-256 digests of verified Auth0 subjects,
-- not plaintext subject identifiers. Roles are admin provisioned.

CREATE TABLE IF NOT EXISTS cp_joint_payments (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES cp_joint_accounts(account_id),
    initiator TEXT NOT NULL,
    primary_sub TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN (
        'awaiting_primary','ready','approved','declined',
        'processing','submitted','unknown','completed','failed')),
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    recipient TEXT NOT NULL,
    reason TEXT NOT NULL,
    assessment TEXT NOT NULL,
    decision_by TEXT,
    nessie_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cp_joint_payments_account_created_idx
    ON cp_joint_payments (account_id, created_at DESC, id DESC);

-- Optional read-only verification:
-- SELECT 'nessie_links' AS table_name, COUNT(*) FROM cp_nessie_links
-- UNION ALL SELECT 'joint_accounts', COUNT(*) FROM cp_joint_accounts
-- UNION ALL SELECT 'joint_payments', COUNT(*) FROM cp_joint_payments;
