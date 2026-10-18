# CreditPilot — Seed the Nessie Sandbox

**Owner:** Bindhu (Nessie integration). Everyone else consumes the generated IDs and API responses.

## 1. Get the latest code

From PowerShell, inside the Flutter repository:

```powershell
git pull origin main
if (!(Test-Path backend\.env)) { Copy-Item backend\.env.example backend\.env }
notepad backend\.env
```

Set `NESSIE_API_KEY` to **your own** Nessie sandbox key in `backend/.env`. Keep the HTTPS URL unchanged:

```dotenv
NESSIE_API_KEY=YOUR_PRIVATE_KEY
NESSIE_BASE_URL=https://prod-api.nessieisreal.com
```

Do not push the real `.env`, and rotate a key that has already been exposed in chat.

## 2. Preview then insert

```powershell
python backend\scripts\seed_nessie.py
python backend\scripts\seed_nessie.py --apply
python backend\scripts\seed_nessie.py --verify
```

**Only `--apply` inserts data**. The default command previews the data without contacting Nessie. On success, the script writes `backend/seed_manifest.json` with the real sandbox IDs. This file is deliberately Git-ignored and can be shared directly with teammates if they use the same sandbox; it contains no API key.

### Records created in Nessie

| Record | Demo value |
|---|---|
| Sarah (fictional customer) | Primary app user |
| Jamie (fictional customer) | Trusted partner |
| Sarah checking | $500 |
| Sarah savings | $1,200 |
| Card A | $750 balance |
| Card B | $200 balance |
| Shared demo checking | $2,000 (owned by Sarah in Nessie) |
| Jamie checking | $350 |
| Grocery, fuel, cafe | 3 fictional merchant records |
| Rent due +3 days (app-only fallback) | $400 |
| Electricity due +7 days (app-only fallback) | $150 |
| Internet due +12 days (app-only fallback) | $100 |

The three upcoming bills total $650, versus $500 in checking: a projected $150 shortfall.

### NOT written to Nessie

The script puts these fictional values in `seed_manifest.json.app_scenario` for our own backend: credit limits, rewards rates, statement close offsets, utilization targets, simulated partner association, a proposed unusual $850 payment and an unexpected $1,000 emergency.

Nessie account types are not equivalent to live credit bureau reports; and **shared_demo is not a real jointly owned account**. Nessie doesn't approve, pause or intercept all external bank payments.

### No transactions yet

This **Stage 1** seeder sets initial balances directly and creates unpaid future bills. It does **not** create deposits, purchases, credit-card repayments or transfers. That deliberately avoids accidentally changing the seeded balances before we've verified how the sandbox applies transaction writes. Stage 2 can add a realistic transaction history after verification.

## 3. Team dependencies

1. **Bindhu:** runs the seed on one Nessie key and verifies all records exist.
2. **Parvathi:** receives the manifest IDs and builds FastAPI `GET /accounts` and `GET /forecast` responses from Nessie.
3. **Rohith:** uses the exact balances, bill due dates and app-only card metadata to calculate risk and rewards.
4. **Ajit:** uses deterministic backend results in Gemini explanations and builds Auth0-protected access.

**Do not run `--apply` from four different computers**. Run it once with the shared demo sandbox key, then distribute the generated manifest IDs securely. Re-running using the same local manifest is designed to reuse records. `--apply` in a new directory with a new manifest generates a separate dataset.

**Definition of done:** Bindhu confirms `--verify` succeeds; Flutter displays the seeded checking and savings accounts and three future bills from a backend response.


## Current Nessie bill API limitation and safe fallback

**Observed October 17:** An incomplete Rent bill was created in the sandbox. `PUT /bills/{id}`
rejects `upcoming_payment_date` as an extra field, while `GET /bills/{id}`
requires it, even after a PUT supplying `recurring_date`. This is an
incompatible read/write validation behavior; we cannot repair it reliably
from the documented REST API.

To prevent more malformed bills or accidental deletion, the seed script now:
- Reuses the 2 customers, 6 accounts and 3 merchants already created in Nessie.
- Stores **all three planned bills locally in** `backend/seed_manifest.json`
  at `app_bills`; each has `source: app_simulation` and an expected date.
- Preserves the malformed rent record without deleting it.
- Reports `APP-ONLY OK` for the local bills during `--verify` and explicitly
  reports the old Nessie bill as `UNREADABLE`.
- Never claims the simulated bills were persisted successfully in Nessie.

In the app backend, the bill forecast should temporarily read
`seed_manifest.json["app_bills"]`, rather than Nessie `GET /bills`.
This keeps the **Nessie integration real for accounts**, while avoiding
misrepresenting the bill source. Once the Nessie API is corrected, bills can
be migrated into the sandbox and the fallback removed.

### Run now

```powershell
git pull origin main
python backend\scripts\seed_nessie.py --apply
python backend\scripts\seed_nessie.py --verify
```

Do **not** run the old `--repair-bills` command: it is intentionally disabled
to avoid deleting a known bill when Nessie's read/write models disagree.
Keep your original `seed_manifest.json`; never share `backend/.env` or the API key.

## Seed 500 actual Nessie accounts

The existing `seed_nessie.py` creates only 2 customers and 6 accounts. The new
`seed_nessie_bulk.py` creates **500 fictional Nessie customers and 500 checking accounts**
(one per customer); it is separate from the 500 synthetic SQLite/TigerData profiles.

Run these commands from the repository root after configuring your private Nessie API key in `backend/.env`:

```powershell
git pull origin main
python backend\scripts\seed_nessie_bulk.py
python backend\scripts\seed_nessie_bulk.py --apply
python backend\scripts\seed_nessie_bulk.py --verify
```

The default invocation previews only; `--apply` creates records; `--verify`
reads back each created customer and account from the Nessie API.
To test 5 first, use `--count 5 --apply`, then `--count 5 --verify`,
then `--count 500 --apply` and finally `--verify`.

The restart-safe checkpoint is `backend/nessie_bulk_manifest.json` (Git-ignored).
Use the same API key and preserve this manifest to resume.
Optional `--full-portfolio --apply` seeds 4-8 accounts per customer, more than
500 accounts total. Choose that mode before the first run, and keep that
flag for subsequent apply/verify calls.

Bulk seeding creates Nessie accounts only: it does NOT upload synthetic
transactions or future bills, and does not automatically link the new customers
to Auth0 or make them visible in the existing app demo. The current Nessie
app still uses its existing per-user `seed_manifest.json` mappings.
No real transactions, payments, or transfers are created.

## Existing username/password login → Nessie via TigerData

For this login-only prototype, an administrator first creates a user in the **Auth0 Database connection**. In Auth0 Authentication > Database, enable username login (requires username), disable public signups, and enable that connection on the CreditPilot application. The user types **username and password on hosted Auth0 Universal Login**. Auth0 verifies them and returns a signed token containing the same unique `sub` user ID every login. CreditPilot never handles passwords.

In `backend/.env`, set `AUTH_MODE=auth0`, `DEMO_DATA_MODE=nessie`, `DEMO_STORE=sqlite`, `TIGERDATA_DATABASE_URL`, `NESSIE_API_KEY`, `AUTH0_DOMAIN`, and `AUTH0_AUDIENCE`. Once `seed_nessie_bulk.py --apply` is done, from project root run:

```powershell
python backend\scripts\link_nessie_user.py --subject "auth0|YOUR_USER_ID" --slot 0
```

This binds the Auth0 subject hash to a specific **pre-provisioned** Nessie customer and their account IDs in TigerData. Backend `/api/me` looks up the verified `sub`, and `/api/dashboard` fetches the matching account balances from Nessie. Do this once per authorized demo user; user IDs are provided by Auth0, not typed into the app or trusted from the browser. The 500 Nessie customers do **not** automatically constitute 500 Auth0 login identities.
