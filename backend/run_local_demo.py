"""Loopback-only development harness using fictional local portfolios.

Run directly: python backend/run_local_demo.py
This does not change the production app's Auth0 requirement. Never deploy this
runner: it intentionally supplies a fixed demo identity instead of real login.
"""
import os
from pathlib import Path


def run():
    if os.getenv("APP_ENV", "development") == "production":
        raise RuntimeError("The local demo runner cannot run in production")
    root = Path(__file__).resolve().parent
    # Keep local demo state and all external credentials separate from real setup.
    os.environ.update({
        "APP_ENV": "development", "AUTH_MODE": "demo",
        "DEMO_DATA_MODE": "nessie", "DEMO_STORE": "sqlite",
        "PAYMENT_MODE": "simulate", "TIGERDATA_DATABASE_URL": "",
        "NESSIE_API_KEY": "", "GEMINI_API_KEY": "",
        "DB_PATH": str(root / "local_demo.sqlite3"),
        "CORS_ORIGINS": "http://localhost:8080,http://127.0.0.1:8080",
    })
    import main as api
    import uvicorn

    # Explicit test-harness injection, identical in principle to TestClient
    # dependency overrides. main:app keeps its stricter real-auth startup guards.
    api.DATA_MODE = "synthetic"
    api.app.dependency_overrides[api.actor] = lambda: "local-demo|member"
    print("LOCAL DEMO: fictional SQLite data; no Auth0, Nessie or Gemini connection.")
    uvicorn.run(api.app, host="127.0.0.1", port=8765, access_log=True)


if __name__ == "__main__":
    run()
