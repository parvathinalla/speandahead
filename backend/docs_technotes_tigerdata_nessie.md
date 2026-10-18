# CreditPilot: Nessie + Auth0 + TigerData (no synthetic CSV)

Bank balances and account records come from **Capital One Nessie**.
TigerData stores the mapping from a *verified* Auth0 user to Nessie IDs,
plus the app's joint-account consent metadata and payment request states.
Never import fake `cp_demo_profiles` into the production Nessie-backed flow.

## 1. Select and inspect the correct TigerData service

In TigerData Console, open the exact service your backend connection URI
points to. SQL Editor (read-only):

```sql
SELECT current_database(), current_schema();
SELECT to_regclass('public.cp_nessie_links') AS nessie_links,
       to_regclass('public.cp_joint_accounts') AS joint_accounts,
       to_regclass('public.cp_joint_payments') AS joint_payments;
```

Note: `db-97301` was previously empty. The reported 500/500
`cp_demo_profiles` were synthetic profiles from an unknown connection target.
Do not assume they are in `db-97301`, or that they represent Nessie users.

## 2. Create the tables

Open `backend/sql/nessie_joint_tigerdata.sql`, copy its SQL into the
**selected** TigerData service's SQL Editor, and execute it. It is idempotent,
does not delete anything, and creates these tables:

- `cp_nessie_links`: SHA-256(Auth0 subject) → Nessie customer + account IDs
- `cp_joint_accounts`: one primary and one dependent hash per joint account,
  optional approval threshold (integer cents), allowed recipients
- `cp_joint_payments`: immutable payment-request identity, saved decisions,
  state, Nessie receipt ID, and review data

No CSV upload is required to create empty relational tables. No user account
mapping should be invented: real Nessie IDs come from your Nessie seed manifest
and are linked only by an authorized operator.

## 3. Backend environment

Keep all credentials in ignored `backend/.env`, not the repo/Flutter:

```dotenv
AUTH_MODE=auth0
DEMO_DATA_MODE=nessie
DEMO_STORE=sqlite
JOINT_STORE=tigerdata
TIGERDATA_DATABASE_URL=postgresql://.../tsdb?sslmode=verify-full
NESSIE_API_KEY=YOUR_SECRET
PAYMENT_MODE=simulate
```

Also configure your actual Auth0 domain/audience. No live bank transactions
can be made; all Nessie records are sandbox fictional data. Keep
`PAYMENT_MODE=simulate` until you intentionally perform a tested sandbox
transfer with explicit user confirmation. The joint execution endpoint will
refuse execution while payment mode is simulate.

### If you have existing joint records in local SQLite

Before switching to `JOINT_STORE=tigerdata`, copy the existing records with
these commands **on the machine that owns that SQLite database**:

```powershell
py backend/scripts/migrate_joint_to_tigerdata.py
py backend/scripts/migrate_joint_to_tigerdata.py --apply
```

This step reads `DB_PATH` (or `backend/creditpilot.sqlite3`) and copies
`joint_accounts` and `joint_payments` in one PostgreSQL transaction,
hashing verified Auth0 subjects. It never deletes SQLite files. Conflicting
records cause rollback. If there are no joint tables/data yet, just create
the new tables and provision new test accounts instead.

### Provision one authenticated Nessie user

You must **already have** a valid, private `backend/nessie_bulk_manifest.json`
from `seed_nessie_bulk.py` and one verified Auth0 subject. This command
links only that subject; no self-service privilege escalation:

```powershell
py backend/scripts/link_nessie_user.py --subject 'auth0|ACTUAL_SUBJECT' --slot 0
```

The customer and account IDs come from the Nessie manifest. The supplied
Auth0 subject is hashed before writing to `cp_nessie_links`. The operator
must check that slot's customer/account relationship before linking.

### Provision joint membership (optional)

See `backend/JOINT_ACCOUNTS.md`. With `JOINT_STORE=tigerdata` the same
`link_joint_account.py` command writes to `cp_joint_accounts`, hashing both
subjects. Member roles and allowed recipients cannot be assigned from Flutter.

## 4. Verify

Run these in the **same target** TigerData service:

```sql
SELECT COUNT(*) AS mapped_auth0_users FROM public.cp_nessie_links;
SELECT COUNT(*) AS joint_accounts FROM public.cp_joint_accounts;
SELECT COUNT(*) AS joint_payments FROM public.cp_joint_payments;
```

The counts may legitimately be zero before you provision real Nessie mappings.
Never seed invented Auth0-Nessie relationships to force these counts higher.

## What still uses SQLite?

`main.py`'s general `actions` table, including saved simulated AutoPay
plans and non-joint transfer idempotency records, still uses local SQLite.
This migration changes the **joint consent/payments** store only. Multi-instance
persistence of general actions is a separate change and must be tested before
deploying multiple backend replicas.

Do not enable `JOINT_STORE=tigerdata` until existing active SQLite joint
requests have been migrated and read back. Never repeat an uncertain Nessie
payment when a prior request is `processing` or `unknown`.
