# CreditPilot AI / SpendAhead

**Before you spend, see what happens next.** A Flutter + FastAPI hackathon prototype built using Capital One's Nessie mock-banking API and deterministic financial scenario analysis.

## Five features

1. **Bill Forecast:** Detect a possible cash shortfall before upcoming payments, and preview a savings-to-checking transfer.
2. **Smart Card Advisor:** Compare rewards with credit utilization before a purchase.
3. **Joint Account Pre-check:** Flag an unusual *proposed in-app payment* and request a simulated partner confirmation.
4. **Emergency Readiness:** Estimate whether cash, after protecting scheduled bills, can cover a surprise expense.
5. **Utilization AutoPay:** Calculate an affordable paydown toward a target ratio; optionally simulate a savings transfer first. Plans are simulated and are **not real bank autopay**.

## Technology

Flutter mobile/web → FastAPI → deterministic financial engine + Nessie sandbox. SQLite stores demo approvals/plans, Auth0 verifies access tokens when configured, Gemini can explain calculated results when configured.

**Data truth:** Nessie supplies fictional balances. Our own scenario data supplies upcoming bills, rewards rates, credit limits, statement dates, and simulated joint partner information. We label all of these separately.

## Run the app

### Backend (Windows PowerShell)

```powershell
git pull origin main
python -m pip install -r backend/requirements.txt
if (!(Test-Path backend\.env)) { Copy-Item backend\.env.example backend\.env }
notepad backend\.env
python backend\scripts\seed_nessie.py --apply
python backend\scripts\seed_nessie.py --verify
python -m uvicorn main:app --app-dir backend --host 127.0.0.1 --port 8000 --reload
```

Open `http://127.0.0.1:8000/docs` for API docs.

### Flutter (in another terminal)

```powershell
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For Android emulator, use `http://10.0.2.2:8000`.

For complete routes, security notes and cloud deployment instructions, see [Backend README](backend/README.md). For Nessie seeding limitations, see [SEEDING.md](backend/SEEDING.md).

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
| Bindhu | Flutter UI, Nessie adapter and authentication integration |
| Parvathi | FastAPI routes, sandbox actions, persistence, deployment |
| Rohith | Financial calculations and scenario tests |
| Ajit | Auth0 integration support, Gemini explanations, end-to-end QA |

## Important limitations

This is a hackathon **demo**, not a consumer banking product. It cannot intercept bank-level joint-owner activity, guarantee credit scores, initiate real credit-card issuer AutoPay, or send reports to bureaus. `AUTH_MODE=demo` is solely for fictional local demo data; production must validate Auth0 tokens and use HTTPS. No real API key belongs in the repository.

## Repository

https://github.com/parvathinalla/speandahead
