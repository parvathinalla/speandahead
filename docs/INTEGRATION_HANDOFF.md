# CreditPilot — Final Integration Handoff (October 17, 2026)

## What is implemented in GitHub

- [x] Five Flutter screens dynamically invoke FastAPI instead of silently using invented offline data.
- [x] Nessie API adapter reads the six seeded sandbox accounts on the backend.
- [x] Bills read from `backend/seed_manifest.json.app_bills` because Nessie bill read/write schemas are inconsistent.
- [x] Deterministic 14-day bill forecast and safe savings transfer recommendation.
- [x] Best-card rewards/utilization comparison and combined purchase decision.
- [x] Joint unusual **proposed in-app** payment simulation + second demo actor confirmation.
- [x] Emergency expense affordability and protected-bill calculation.
- [x] Smart AutoPay preview and what-if savings-funding preview.
- [x] Explicitly confirmed simulated actions, SQLite status, idempotency and no default Nessie writes.
- [x] Auth0 bearer verification code and demo-user allowlist (requires configuration).
- [x] Optional Gemini explanation API with deterministic fallback (requires API key).
- [x] Backend financial/API unit tests and Flutter analysis/widget CI.
- [x] Dockerfile, environment template, setup documentation and read-only smoke test.

## Manual integration work that requires local access or credentials

### Bindhu — Signup/Login + Flutter
- [ ] Finish Auth0 Flutter login/signup and obtain an access token for FastAPI audience.
- [ ] Assign `ApiService.bearerToken` after successful login; clear token on logout.
- [ ] Verify signing in and out does not leak the prior demo identity.
- [ ] Run on Windows Chrome or Android emulator with the documented API URL.
- [ ] Review all five connected screens visually and fix overflow on smaller phones.

### Parvathi — Nessie + backend + deployment
- [ ] Rotate any Nessie key shared outside the backend and keep the rotated key in `backend/.env`.
- [ ] Run the latest `seed_nessie.py --apply` and `--verify` to write the local bill fallback; retain existing manifest.
- [ ] Start FastAPI and run `python backend\scripts\smoke_test.py` against real sandbox balances.
- [ ] Confirm `/api/dashboard`, `/api/bills/forecast`, `/api/cards/evaluate` return correct values.
- [ ] Provision Vultr or other hosting with HTTPS and secret env vars; do not publish with `AUTH_MODE=demo`.
- [ ] Set Auth0 allowed subjects to restrict access to fictional accounts.

### Rohith — Finance logic acceptance
- [ ] Cross-check actual seeded account balances/credit limits with the sample $120 grocery example.
- [ ] Add more failure-mode scenarios around insufficient savings, multiple bills on the same day, and delayed income.
- [ ] Confirm AutoPay never allocates protected bill or savings reserve money.
- [ ] Explain how card balance/reporting-date/rewards fields are mocked rather than Nessie native.

### Ajit — Auth0 + Gemini + demo QA
- [ ] Configure Auth0 domain/audience, `AUTH0_ALLOWED_SUBS`, and `JOINT_PARTNER_SUB`.
- [ ] Add `GEMINI_API_KEY` to backend secrets if using AI explanations and test generation quality.
- [ ] Run end-to-end user journeys with Flutter and record a 3-minute demo.
- [ ] Validate no UI claims that bank-level joint transaction blocking or real bureau autopay exists.

## Never claim these as completed

- No evidence yet of this assistant running private-key live Nessie API calls.
- Nessie bills are an app-only fallback; the earlier malformed rent record is untouched.
- The AutoPay plan is stored **but no payment scheduler or credit-issuer integration runs**.
- Neither real banking payments nor bureau reporting is supported.
- Auth0 app login and public cloud deployment remain unverified on your team's accounts.

## Commands to finish the first live test

```powershell
git pull origin main
python -m pip install -r backend/requirements.txt
python backend\scripts\seed_nessie.py --apply
python -m uvicorn main:app --app-dir backend --host 127.0.0.1 --port 8000 --reload
```

In a *second* terminal:

```powershell
python backend\scripts\smoke_test.py
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```
