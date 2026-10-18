# CreditPilot AI / SpendAhead

**Before you spend, see what happens next.** A Flutter + FastAPI hackathon prototype built using Capital One's Nessie mock-banking API and deterministic financial scenario analysis.

## Five features

1. **Bill Forecast:** Detect a possible cash shortfall before upcoming payments, and preview a savings-to-checking transfer.
2. **Smart Card Advisor:** Compare rewards with credit utilization before a purchase.
3. **Joint Account Pre-check:** Flag an unusual *proposed in-app payment* and request a simulated partner confirmation.
4. **Emergency Readiness:** Estimate whether cash, after protecting scheduled bills, can cover a surprise expense.
5. **Utilization AutoPay:** Calculate an affordable paydown toward a target ratio; optionally simulate a savings transfer first. Plans are simulated and are **not real bank autopay**.

## Technology

Flutter mobile/web → FastAPI → deterministic financial engine + Nessie sandbox. SQLite stores demo approvals/plans, Auth0 validates access tokens on the backend and provides hosted login/signup, Gemini can explain calculated results when configured.

**Data truth:** Nessie supplies fictional balances. Our own scenario data supplies upcoming bills, rewards rates, credit limits, statement dates, and simulated joint partner information. We label all of these separately.

## Run the app

### Backend (Windows PowerShell)

```powershell
git pull origin main
python -m pip install -r backend/requirements.txt
if (!(Test-Path backend\.env)) { Copy-Item backend\.env.example backend\.env }
notepad backend\.env
python backend\scripts\seed_nessie.py --apply
python -m uvicorn main:app --app-dir backend --host 127.0.0.1 --port 8765
```

For **real Auth0 signup/login**, set `AUTH_MODE=auth0`, `AUTH0_DOMAIN`,
`AUTH0_AUDIENCE` in backend/.env and restart FastAPI.

### Flutter (in another terminal)

```powershell
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:8765 --dart-define=AUTH0_DOMAIN=YOUR_TENANT.us.auth0.com --dart-define=AUTH0_WEB_CLIENT_ID=YOUR_PUBLIC_WEB_CLIENT_ID --dart-define=AUTH0_AUDIENCE=https://api.creditpilot.example
```

Both **Log In** and **Create Account** use Auth0 Universal Login / PKCE.
Newly registered users see a safe account-linking screen until an administrator
provisions **their own** Nessie sandbox mapping. See
[Auth0 Production Setup](docs/AUTH0_PRODUCTION_SETUP.md).

**If Auth0 isn't configured yet**, local debug mode with a fictional account
can be enabled by compiling Flutter with `--dart-define=DEV_DEMO_AUTH=true`
and retaining backend `AUTH_MODE=demo`. It cannot be enabled in a release
build. It does not demonstrate real authentication.

Deployment templates: [HTTPS Docker Compose](deploy/README.md). Backend
endpoints: [Backend README](backend/README.md). Nessie bill limitation:
[SEEDING.md](backend/SEEDING.md).

## Testing

```powershell
python -m pip install -r backend/requirements-dev.txt
$env:PYTHONPATH = "backend"
python -m pytest -q backend/tests
flutter analyze --no-fatal-infos lib test
flutter test
```

GitHub Actions checks backend tests and Flutter analysis/tests.

## Team ownership

| Owner | Area |
|---|---|
| Bindhu | Flutter UI, Auth0 tenant connection and device verification |
| Parvathi | FastAPI routes, Auth0 security, sandbox isolation, deployment |
| Rohith | Financial calculations and scenario tests |
| Ajit | Auth0 integration support, Gemini explanations, end-to-end QA |

## Important limitations

This is a hackathon **demo**, not a consumer banking product. It cannot intercept bank-level joint-owner activity, guarantee credit scores, initiate real credit-card issuer AutoPay, or send reports to bureaus. `AUTH_MODE=demo` is solely for fictional local demo data; production must validate Auth0 tokens and use HTTPS. No real API key belongs in the repository.

## Repository

https://github.com/parvathinalla/speandahead
