# CreditPilot AI — Backend Implementation

This FastAPI backend powers all **5 hackathon features**. Account balances come from Capital One's **Nessie sandbox**, while upcoming bills, credit limits, rewards, bureau statement timing, and joint-owner relationships are clearly labeled **fictional app scenario data**.

## Start locally (Windows PowerShell)

From the repository root:

```powershell
git pull origin main
python -m pip install -r backend/requirements.txt
if (!(Test-Path backend\.env)) { Copy-Item backend\.env.example backend\.env }
notepad backend\.env
python backend\scripts\seed_nessie.py --apply
python backend\scripts\seed_nessie.py --verify
python -m uvicorn main:app --app-dir backend --host 127.0.0.1 --port 8000 --reload
```

Open [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs) for interactive API docs, or [http://127.0.0.1:8000/health](http://127.0.0.1:8000/health) for basic readiness.

In a second terminal, run Flutter:

```powershell
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For Android emulator, use `--dart-define=API_BASE_URL=http://10.0.2.2:8000`. For a real phone, your FastAPI host must be reachable on the local network and a production deployment must use HTTPS.

## Feature APIs

| Purpose | Endpoint | Source / behavior |
|---|---|---|
| Health | `GET /health` | Server config only, no secrets |
| Home | `GET /api/dashboard` | Real Nessie balances + app-only bills |
| Accounts | `GET /api/accounts` | Real Nessie sandbox |
| Bills | `GET /api/bills` | Local seeded bill scenario |
| Forecast | `POST /api/bills/forecast` | Deterministic timeline |
| Rewards | `POST /api/cards/evaluate` | Real card balances + simulated rewards and limits |
| Pre-purchase | `POST /api/decisions/purchase` | Rewards + bill cashflow + optional emergency |
| Joint pre-check | `POST /api/joint/evaluate` | In-app proposal ONLY |
| Joint approve | `POST /api/joint/proposals` and `POST /api/joint/proposals/{id}/decision` | Demo-only partner consent |
| Emergencies | `POST /api/emergency/evaluate` | Available funds minus protected bills and reserve |
| Utilization | `POST /api/autopay/preview` | Affordable paydown; no actual card payment |
| What-if AutoPay | Same, with `assumed_savings_transfer` | Simulated funding without moving money |
| Save AutoPay plan | `POST /api/autopay/plans` | SQLite plan record, NOT a payment scheduler |
| Cancel/list plans | `POST .../{id}/cancel`, `GET .../plans` | Local plans only |
| Transfer preview | `POST /api/transfers/preview` | Savings reserve guard |
| Transfer execute | `POST /api/transfers/execute` | Simulated by default; explicit confirmed action |
| AI explanations | `POST /api/ai/explain` | Optional Gemini; no account keys in prompt |

**Do not interpret the saved AutoPay plan as scheduled at the bank.** Early repayments and credit bureau reporting require issuer/payment rails beyond Nessie.

## Payment safety

- All financial calculations are deterministic, not invented by Gemini.
- Savings-transfer proposals require explicit confirmation and a unique idempotency key.
- `PAYMENT_MODE=simulate` (default) records a simulated action in SQLite; it does **not** change Nessie balances.
- `PAYMENT_MODE=nessie` is an optional sandbox transfer mode and requires `AUTH_MODE=auth0`. It has **not been verified with this project's private Nessie key**. Enable only after end-to-end sandbox testing; an unknown transfer outcome is not automatically retried.
- Joint proposals are app-level demonstration records, **not bank-wide transaction locks**.
- Credit utilization target 29% is a configurable example, not a score guarantee.

## Authentication / environment

**Local hackathon:** `AUTH_MODE=demo`, `PAYMENT_MODE=simulate`. This is deliberately unsecured synthetic demo data and must not be publicly deployed.

**With Auth0:** Set `AUTH_MODE=auth0`, `AUTH0_DOMAIN`, `AUTH0_AUDIENCE`, and `AUTH0_ALLOWED_SUBS` (comma-separated authorized Auth0 subject IDs for the fictional seed sandbox). Tokens are verified against Auth0 JWKS, expected issuer, audience and expiry. Bindhu should pass the Auth0 bearer access token to `ApiService.bearerToken` after login. Set `JOINT_PARTNER_SUB` to the partner's Auth0 subject before exposing joint approvals outside demo mode. For optional Nessie sandbox transfers, also set `NESSIE_TRANSFER_ALLOWED_SUB` to the one Auth0 subject allowed to initiate sandbox transfers.

**Gemini:** Set `GEMINI_API_KEY` locally. Without it, `/api/ai/explain` returns a deterministic explanation with `ai_used=false`. This allows offline demonstrations.

Never push `backend/.env` or `backend/seed_manifest.json`. The manifest contains sandbox object IDs, not secrets, but is private local scenario state. `SEED_MANIFEST_PATH` may point to an external JSON file when deploying.

## Tests

```powershell
python -m pip install -r backend/requirements-dev.txt
$env:PYTHONPATH = "backend"
python -m pytest -q backend/tests
```

GitHub Actions runs backend and Flutter checks. The financial tests use fake Nessie data and no credentials.

## Deployment

```powershell
docker build -f backend/Dockerfile -t creditpilot-backend .
```

Deploy as a container with HTTPS ingress, secured Auth0, a protected Nessie key, a persistent SQLite volume (or production database), and a mounted `seed_manifest.json`. **Never expose `AUTH_MODE=demo` on a public endpoint.**

### Team ownership / handoff

- **Bindhu:** Flutter UI and Nessie seed/integration. Own the Auth0 Flutter login connection currently being built.
- **Parvathi:** FastAPI feature API, simulation actions, persistence, deployment.
- **Rohith:** deterministic calculations in `backend/finance_engine.py`, tests and edge cases.
- **Ajit:** Auth0 verification configuration, Gemini prompt quality, integration QA and demo.

**Requires live verification:** API calls with your private Nessie key, Auth0 login handshake, mobile device networking, and deployed hosting.
