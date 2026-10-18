# Run the merged project locally

The team integration includes main's connected Auth0/API application, Rohith's
domain engines and tests, and Bindhu's Nessie adapter and fixture UI components.
The application entry point remains `lib/main.dart`, using the connected `/api`
screens and real `AuthSession`. Bindhu's alternative `/v1` screens use a simulated
auth service and fixture responses, so they are retained separately in
`FixtureShell` and the fixture router instead of replacing real authentication.
They still require a backend contract migration before becoming the live UI.

The provider fixture is under `provider_demo` in `fixtures/seed_profile_v1.json`;
the deterministic engine scenarios retain their `common` / `scenarios` contract.
The Nessie adapter reads `provider_demo`, and its fixture lookup now works
regardless of the current directory. All backend test directories are discovered.

## No-credentials development run

From the repository root:

```powershell
.\backend\.venv\Scripts\python.exe -m pip install -r backend/requirements-dev.txt
.\backend\.venv\Scripts\python.exe backend/run_local_demo.py
```

In another terminal:

```powershell
flutter pub get
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080 --dart-define=DEV_DEMO_AUTH=true --dart-define=API_BASE_URL=http://127.0.0.1:8765
```

Open http://127.0.0.1:8080. The development runner binds only to loopback, disables
external credentials, uses a fixed fictional identity and saves generated profiles
in the ignored `backend/local_demo.sqlite3`. It is not a real Auth0/Nessie test.
Never deploy `run_local_demo.py`. Production uses `main:app` with Auth0, HTTPS and
the team's private environment configuration, as documented in the main README.

## Verification

```powershell
.\backend\.venv\Scripts\python.exe -m pytest -q backend/tests
flutter analyze --no-fatal-infos lib test
flutter test
.\backend\.venv\Scripts\python.exe backend/scripts/smoke_test.py --url http://127.0.0.1:8765 --synthetic
```

If Windows reports missing native symlink support after downloading dependencies,
use `--no-pub` with `flutter analyze`, `flutter test` and `flutter run` for the web
target. Native Windows builds still need the normal Windows developer setup.

The API currently uses `backend/finance_engine.py`; the independently tested
`backend/app/domain` functions remain available for the planned typed-contract
migration. Merging source code does not by itself replace the API's calculations.
