"""CreditPilot API: real Nessie accounts + explicit simulated financial scenarios.

Run: uvicorn main:app --app-dir backend --reload
Never place Nessie or Gemini API keys in Flutter or GitHub.
"""
import asyncio
import hashlib
from datetime import date, timedelta
from decimal import Decimal
from functools import lru_cache
import json
import os
from pathlib import Path
import sqlite3
import time
from typing import Any, Literal, Optional
from uuid import uuid4

import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import jwt

from finance_engine import (
    adaptive_autopay_preview, amount, autopay_preview, card_comparison,
    clamp_positive, emergency,
    forecast, joint_risk, money, next_payment_date, optimize_card_portfolio,
    purchase_guidance
)
import synthetic_bank as demo_bank
from tigerdata_store import TigerDataStore
from nessie_links import NessieLinkStore
from agent_memory import AgentMemory
from agent_service import ask_gemini, extract_trip_plan, snapshot as agent_snapshot
from push_notifications import send_cashflow_warning, send_hurricane_warning
from location_service import nearby_merchants

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")
NESSIE_URL = os.getenv("NESSIE_BASE_URL", "https://prod-api.nessieisreal.com").rstrip("/")
MANIFEST = Path(os.getenv("SEED_MANIFEST_PATH", str(ROOT / "seed_manifest.json")))
SQLITE = Path(os.getenv("DB_PATH", str(ROOT / "creditpilot.sqlite3")))
AUTH_MODE = os.getenv("AUTH_MODE", "demo").strip().lower()
DATA_MODE = os.getenv("DEMO_DATA_MODE", "synthetic" if AUTH_MODE == "auth0" else "nessie").strip().lower()
DEMO_STORE = os.getenv("DEMO_STORE", "sqlite").strip().lower()
ENVIRONMENT = os.getenv("APP_ENV", "development").strip().lower()
TENANTS_DIR = Path(os.getenv("TENANT_MANIFEST_DIR", str(ROOT / "private" / "tenants")))
PAYMENT_MODE = os.getenv("PAYMENT_MODE", "simulate").strip().lower()
GOOGLE_PLACES_API_KEY = os.getenv("GOOGLE_PLACES_API_KEY", "").strip()
ORIGINS = [o.strip() for o in os.getenv("CORS_ORIGINS", "http://localhost:3000,http://localhost:8080,http://127.0.0.1:8080").split(",") if o.strip()]
PUSH_ENABLED = os.getenv("PUSH_NOTIFICATIONS_ENABLED", "false").strip().lower() == "true"
PUSH_DAILY_HOUR = int(os.getenv("PUSH_DAILY_HOUR_LOCAL", "9"))
HURRICANE_SIMULATION_ENABLED = (
    os.getenv("HURRICANE_SIMULATION_ENABLED", "false").strip().lower() == "true"
)

if AUTH_MODE not in ("demo", "auth0"):
    raise RuntimeError("AUTH_MODE must be demo or auth0")
if DATA_MODE not in ("nessie", "synthetic"):
    raise RuntimeError("DEMO_DATA_MODE must be nessie or synthetic")
if DEMO_STORE not in ("sqlite", "tigerdata"):
    raise RuntimeError("DEMO_STORE must be sqlite or tigerdata")
if DEMO_STORE == "tigerdata":
    if AUTH_MODE != "auth0":
        raise RuntimeError("TigerData backend requires Auth0 authentication")
    if not os.getenv("TIGERDATA_DATABASE_URL"):
        raise RuntimeError("Set TIGERDATA_DATABASE_URL as a server-side secret")

if DATA_MODE == "synthetic" and AUTH_MODE != "auth0":
    raise RuntimeError("Synthetic multiuser accounts require real Auth0 login")
if PAYMENT_MODE not in ("simulate", "nessie"):
    raise RuntimeError("PAYMENT_MODE must be simulate or nessie")
if PAYMENT_MODE == "nessie" and AUTH_MODE == "demo":
    raise RuntimeError("Nessie transfer execution requires AUTH_MODE=auth0; demo stays simulation-only")
if ENVIRONMENT not in ("development", "test", "production"):
    raise RuntimeError("APP_ENV must be development, test, or production")
if PUSH_DAILY_HOUR not in range(24):
    raise RuntimeError("PUSH_DAILY_HOUR_LOCAL must be between 0 and 23")
if ENVIRONMENT == "production":
    if AUTH_MODE != "auth0":
        raise RuntimeError("Production must use AUTH_MODE=auth0")
    if not os.getenv("AUTH0_DOMAIN") or not os.getenv("AUTH0_AUDIENCE"):
        raise RuntimeError("Production requires Auth0 issuer and audience")
    if "*" in ORIGINS or any(not x.startswith("https://") for x in ORIGINS):
        raise RuntimeError("Production CORS must use explicit HTTPS origins")
    if PAYMENT_MODE != "simulate":
        raise RuntimeError("Live sandbox transfers not enabled in production")


app = FastAPI(title="CreditPilot AI API", version="1.0", description="Hackathon financial decision simulator")
app.add_middleware(CORSMiddleware, allow_origins=ORIGINS,
                   allow_credentials=True, allow_methods=["GET", "POST"],
                   allow_headers=["Authorization", "Content-Type", "X-Demo-User"])


@lru_cache(maxsize=1)
def tiger_store() -> TigerDataStore:
    if DEMO_STORE != "tigerdata":
        raise RuntimeError("TigerData storage is not selected")
    return TigerDataStore(os.getenv("TIGERDATA_DATABASE_URL", ""))


def using_tigerdata() -> bool:
    return DATA_MODE == "synthetic" and DEMO_STORE == "tigerdata"


def using_nessie_links() -> bool:
    return (AUTH_MODE == "auth0" and DATA_MODE == "nessie"
            and bool(os.getenv("TIGERDATA_DATABASE_URL")))


@lru_cache(maxsize=1)
def nessie_links() -> NessieLinkStore:
    return NessieLinkStore(os.getenv("TIGERDATA_DATABASE_URL", ""))


@lru_cache(maxsize=1)
def agent_memory() -> AgentMemory:
    # Independent of whether Nessie or a synthetic portfolio supplies data.
    pg_url = os.getenv("TIGERDATA_DATABASE_URL", "").strip() or None
    store = AgentMemory(ROOT / "private" / "agent_memory.sqlite3", pg_url)
    store.init()
    return store


def db():
    SQLITE.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(SQLITE), timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("""CREATE TABLE IF NOT EXISTS actions (
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, action_type TEXT NOT NULL,
        status TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS push_devices (
        token TEXT PRIMARY KEY, owner TEXT NOT NULL, platform TEXT NOT NULL,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_push_devices_owner ON push_devices(owner)")
    conn.execute("""CREATE TABLE IF NOT EXISTS hurricane_subscriptions (
        owner TEXT PRIMARY KEY, region TEXT NOT NULL, safety_buffer REAL NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    conn.commit()
    return conn


@app.on_event("startup")
def init_db():
    connection = db()
    try:
        if DATA_MODE == "synthetic":
            if using_tigerdata():
                tiger_store().initialize()
            else:
                demo_bank.initialize(connection)
        if using_nessie_links():
            nessie_links().initialize()
    finally:
        connection.close()
    if PUSH_ENABLED:
        app.state.push_task = asyncio.create_task(push_notification_loop())


@app.on_event("shutdown")
async def stop_push_notifications():
    task = getattr(app.state, "push_task", None)
    if task is not None:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    if request.url.path.startswith("/api/"):
        response.headers["Cache-Control"] = "no-store"
        response.headers["Pragma"] = "no-cache"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Frame-Options"] = "DENY"
    return response


@lru_cache(maxsize=8)
def auth0_jwks(domain: str):
    # Reuse Auth0 JWKS cache instead of fetching its public keys per request.
    return jwt.PyJWKClient(
        "https://" + domain + "/.well-known/jwks.json",
        timeout=5, cache_jwk_set=True, lifespan=300)


def manifest_path_for(user: str) -> Path:
    if AUTH_MODE == "demo":
        return MANIFEST
    if not user or user.startswith("demo-"):
        raise HTTPException(403, "Authenticated user required")
    fingerprint = hashlib.sha256(user.encode("utf-8")).hexdigest()
    return TENANTS_DIR / (fingerprint + ".json")


def has_linked_sandbox(user: str) -> bool:
    if using_nessie_links():
        return nessie_links().get(user) is not None
    if using_tigerdata():
        return tiger_store().get(user) is not None
    if DATA_MODE == "synthetic":
        connection = db()
        try:
            return demo_bank.get(connection, user) is not None
        finally:
            connection.close()
    path = manifest_path_for(user)
    if not path.is_file():
        return False
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if AUTH_MODE == "auth0" and data.get("owner_sub") != user:
            return False
        return bool(data.get("ids", {}).get("accounts") and data.get("app_bills"))
    except (ValueError, OSError, TypeError):
        return False


def manifest(user: str = "demo-sarah") -> dict:
    if using_nessie_links():
        linked = nessie_links().get(user)
        if not linked:
            raise HTTPException(409, "No Nessie account linked to this login")
        return {
            "owner_sub": user, "source": "nessie_sandbox",
            "ids": {"customers": {"primary": linked["customer_id"]},
                    "accounts": linked["accounts"]},
            "app_bills": {}, "app_scenario": {},
        }
    if using_tigerdata():
        try:
            return tiger_store().get_or_claim(user)
        except (ValueError, RuntimeError):
            raise HTTPException(503, "Unable to assign a secure demo profile") from None
    if DATA_MODE == "synthetic":
        connection = db()
        try:
            try:
                return demo_bank.get_or_claim(connection, user)
            except (ValueError, RuntimeError) as exc:
                raise HTTPException(503, str(exc)) from None
        finally:
            connection.close()
    path = manifest_path_for(user)
    if not path.is_file():
        raise HTTPException(409, "No sandbox accounts linked to your profile. Complete onboarding.")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        raise HTTPException(503, "Account mapping unavailable") from None
    if AUTH_MODE == "auth0" and data.get("owner_sub") != user:
        raise HTTPException(403, "Account ownership mismatch")
    if not data.get("ids", {}).get("accounts") or not data.get("app_bills"):
        raise HTTPException(503, "Account scenario not fully provisioned")
    return data


def auth_error(code: str) -> HTTPException:
    """Expose only safe diagnostic category in development, never token contents."""
    if ENVIRONMENT == "development":
        return HTTPException(401, "Invalid authentication token (" + code + ")")
    return HTTPException(401, "Invalid or expired authentication token")


async def actor(authorization: Optional[str] = Header(None),
                x_demo_user: Optional[str] = Header(None)) -> str:
    if AUTH_MODE == "demo":
        # Demo mode is for fictional test data ONLY. Never use as production auth.
        return "demo-" + (x_demo_user or "sarah")[:50]
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Bearer token required")
    domain = os.getenv("AUTH0_DOMAIN", "").strip().replace("https://", "").rstrip("/")
    audience = os.getenv("AUTH0_AUDIENCE", "")
    if not domain or not audience:
        raise HTTPException(503, "Auth0 not configured")
    if "/" in domain or not domain.endswith(".auth0.com") and not os.getenv("AUTH0_ALLOW_CUSTOM_DOMAIN"):
        raise HTTPException(503, "Invalid Auth0 domain configuration")
    token = authorization.split(" ", 1)[1]
    try:
        # JWKS are validated by PyJWT. Blocking network work stays off the event loop.
        jwks = auth0_jwks(domain)
        signing_key = await asyncio.to_thread(jwks.get_signing_key_from_jwt, token)
        claims = jwt.decode(token, signing_key.key, algorithms=["RS256"],
                            audience=audience, issuer="https://" + domain + "/",
                            options={"require": ["exp", "iss", "sub"]})
        # Authenticated signup users can reach /api/me, but have no access
        # to another user's financial sandbox until explicitly provisioned.
        return str(claims["sub"])
    except HTTPException:
        raise
    except jwt.exceptions.ExpiredSignatureError:
        raise auth_error("token_expired") from None
    except jwt.exceptions.InvalidAudienceError:
        raise auth_error("audience_mismatch") from None
    except jwt.exceptions.InvalidIssuerError:
        raise auth_error("issuer_mismatch") from None
    except jwt.exceptions.InvalidSignatureError:
        raise auth_error("invalid_signature") from None
    except jwt.exceptions.PyJWKClientError:
        raise auth_error("signing_key_unavailable") from None
    except jwt.exceptions.DecodeError:
        raise auth_error("malformed_or_opaque_access_token") from None
    except jwt.exceptions.InvalidTokenError:
        raise auth_error("invalid_jwt_claims") from None
    except Exception:
        # Never leak credentials, token bytes, signing keys or remote URLs.
        raise auth_error("verification_unavailable") from None


@app.get("/api/me")
def me(user=Depends(actor)):
    # Claim an isolated synthetic profile on first VERIFIED Auth0 login.
    if DATA_MODE == "synthetic":
        portfolio = manifest(user)
        linked = True
        source = demo_bank.DATA_SOURCE
        profile_id = portfolio["portfolio_id"]
    else:
        linked = has_linked_sandbox(user)
        source = "nessie_sandbox"
        profile_id = None
    return {"authenticated": True, "user_id": user,
            "sandbox_linked": linked, "onboarding_required": not linked,
            "security_mode": AUTH_MODE, "data_source": source,
            "portfolio_id": profile_id, "is_synthetic": DATA_MODE == "synthetic"}


class NessieGateway:
    # Shared per app instance. Five Flutter tabs should not each produce six
    # simultaneous requests to the Nessie demo sandbox.
    def __init__(self):
        self._account_lock = asyncio.Lock()
        self._read_limit = asyncio.Semaphore(2)
        self._account_cache = {}
        self._cache_key = None
        self._cache_until = 0.0

    async def request(self, method: str, path: str, payload=None):
        key = os.getenv("NESSIE_API_KEY", "")
        if not key:
            raise HTTPException(503, "NESSIE_API_KEY missing on backend")
        if not NESSIE_URL.startswith("https://"):
            raise HTTPException(503, "Nessie URL must use HTTPS")

        # Only GET requests are safe to retry. Never retry payment POSTs:
        # their outcome could already have committed at the sandbox.
        attempts = 3 if method == "GET" else 1
        try:
            async with httpx.AsyncClient(timeout=8) as client:
                for attempt in range(attempts):
                    try:
                        response = await client.request(
                            method, NESSIE_URL + path,
                            params={"key": key}, json=payload)
                        response.raise_for_status()
                        return response.json() if response.content else {}
                    except httpx.HTTPStatusError as exc:
                        status = exc.response.status_code
                        transient = status in (429, 500, 502, 503, 504)
                        if method == "GET" and transient and attempt + 1 < attempts:
                            await asyncio.sleep(0.25 * (attempt + 1))
                            continue
                        # Never include request URL or body; Nessie uses key= in URL.
                        raise HTTPException(
                            503 if transient else 502,
                            "Nessie sandbox returned HTTP " + str(status) +
                            (". Please retry shortly." if transient else ".")
                        ) from None
                    except httpx.RequestError:
                        if method == "GET" and attempt + 1 < attempts:
                            await asyncio.sleep(0.25 * (attempt + 1))
                            continue
                        raise HTTPException(
                            503, "Nessie sandbox network request failed; try again."
                        ) from None
                    except (ValueError, TypeError):
                        raise HTTPException(
                            502, "Nessie returned an invalid JSON response"
                        ) from None
        except HTTPException:
            raise

    async def account(self, account_id):
        async with self._read_limit:
            return await self.request("GET", "/accounts/" + account_id)

    async def account_snapshot(self, ids: dict):
        # Cache success only; preserve fresh balances after 12 seconds and
        # invalidate immediately if this backend executes a sandbox transfer.
        names = tuple(ids)
        fingerprint = tuple((name, ids[name]) for name in names)
        if self._cache_key == fingerprint and time.monotonic() < self._cache_until:
            return {name: dict(record) for name, record in self._account_cache.items()}

        # Singleflight: concurrent Flutter screens await the same Nessie reads.
        async with self._account_lock:
            if self._cache_key == fingerprint and time.monotonic() < self._cache_until:
                return {name: dict(record) for name, record in self._account_cache.items()}

            responses = await asyncio.gather(*(self.account(ids[name]) for name in names))
            snapshot = dict(zip(names, responses))
            for name, record in snapshot.items():
                if not isinstance(record, dict) or record.get("_id") != ids[name]:
                    raise HTTPException(502, "Nessie returned a mismatched account ID")
            self._account_cache = snapshot
            self._cache_key = fingerprint
            self._cache_until = time.monotonic() + 12
            return {name: dict(record) for name, record in snapshot.items()}

    async def transfer(self, payer_id, payee_id, value):
        result = await self.request(
            "POST", "/accounts/" + payer_id + "/transfers",
            {"medium": "balance", "payee_id": payee_id,
             "amount": value, "transaction_date": date.today().isoformat(),
             "description": "CreditPilot user-approved sandbox transfer"})
        self._cache_until = 0.0
        return result


def gateway(request: Request):
    current = getattr(request.app.state, "nessie", None)
    if current is None:
        current = NessieGateway()
        request.app.state.nessie = current
    return current


async def accounts(g: NessieGateway, m: dict) -> dict:
    if m.get("source") == demo_bank.DATA_SOURCE:
        return m["accounts"]
    ids = m["ids"]["accounts"]
    if isinstance(g, NessieGateway):
        return await g.account_snapshot(ids)
    # Keep injected test adapters simple; they need only expose account(id).
    names = tuple(ids)
    records = await asyncio.gather(*(g.account(ids[name]) for name in names))
    mapped = dict(zip(names, records))
    for name, rec in mapped.items():
        if rec.get("_id") != ids[name]:
            raise HTTPException(502, "Nessie returned a mismatched account ID")
    return mapped


def account_amount(record):
    return float(money(record.get("balance", 0)))


def card_rules(m, account_values):
    meta = m.get("app_scenario", {})
    rules = {}
    for name, x in meta.items():
        if name not in account_values or not x.get("limit_usd"):
            continue
        item = account_values[name]
        rules[name] = {
            "account_id": item["_id"],
            "balance": account_amount(item),
            "credit_limit": x["limit_usd"],
            "reward_rates": x.get("rewards", {}),
            "display_name": x.get("display_name", item.get("nickname", name)),
            "issuer": x.get("issuer", item.get("institution", "Demo issuer")),
            "last4": x.get("last4", item.get("last4", "0000")),
            "network": x.get("network", item.get("network", "Card")),
            "visual_theme": x.get("visual_theme", "ocean"),
            "benefit_summary": x.get("benefit_summary", "Everyday card rewards"),
        }
    return rules

def bills(m: dict):
    return list(m["app_bills"].values())


def forecast_from(a, m, days=14, reserve=0):
    result = forecast(account_amount(a["checking"]),
                      account_amount(a["savings"]) if "savings" in a else 0,
                      bills(m), days, reserve)
    result["data_sources"] = {
        "balances": m.get("source", "nessie_sandbox"),
        "bills": m.get("source", "local_app_simulation")
                 if m.get("source") == demo_bank.DATA_SOURCE else "local_app_simulation",
    }
    return result


class PushDeviceInput(BaseModel):
    token: str = Field(min_length=20, max_length=4096)
    platform: str = Field(pattern="^(android|ios)$")


def _cashflow_push_text(forecast_result: dict) -> str:
    bill = str(forecast_result.get("first_shortfall_bill") or "An upcoming bill")
    shortfall = float(forecast_result.get("first_shortfall_amount") or 0)
    raw_date = str(forecast_result.get("first_shortfall_date") or "")
    try:
        parsed = date.fromisoformat(raw_date)
        due = parsed.strftime("%b ") + str(parsed.day)
    except ValueError:
        due = "soon"
    return f"Heads up—{bill} may leave you ${shortfall:.2f} short on {due}......"


HURRICANE_EXPENSES = {
    "Food and water": 180.0,
    "Backup power and communications": 120.0,
    "Evacuation transportation": 250.0,
    "Temporary lodging and home protection": 300.0,
}


def _hurricane_region(latitude: float, longitude: float) -> str:
    """Convert coordinates to a broad demo region; precise location is not stored."""
    if 24.3 <= latitude <= 31.2 and -87.8 <= longitude <= -79.7:
        return "Florida"
    if 25.5 <= latitude <= 31.5 and -97.8 <= longitude < -87.8:
        return "Gulf Coast"
    if 25.0 <= latitude <= 36.7 and -81.5 <= longitude <= -75.0:
        return "Atlantic Coast"
    return "your area"


async def hurricane_assessment(owner: str, region: str, safety_buffer: float,
                               gateway_instance=None) -> dict:
    profile = manifest(owner)
    gateway_instance = gateway_instance or getattr(app.state, "nessie", None) or NessieGateway()
    account_values = await accounts(gateway_instance, profile)
    upcoming = forecast_from(account_values, profile, days=14)
    simulated_cost = sum(HURRICANE_EXPENSES.values())
    result = emergency(
        account_amount(account_values["checking"]),
        account_amount(account_values["savings"]),
        upcoming["total_bills_due"], simulated_cost, safety_buffer,
    )
    gap = float(result["potential_gap"])
    usable = float(result["usable_cash_buffer"])
    result.update({
        "scenario": "hurricane_budget_simulation",
        "region": region,
        "horizon_days": 14,
        "additional_expenses": HURRICANE_EXPENSES,
        "covered_amount": round(min(usable, simulated_cost), 2),
        "remaining_cushion": round(max(0.0, usable - simulated_cost), 2),
        "status_message": (
            f"You may be ${gap:.2f} short after upcoming bills and your safety reserve."
            if gap > 0 else
            f"You can cover the simulated costs with ${usable - simulated_cost:.2f} left."
        ),
        "simulation_notice": (
            "Planning simulation only. This is not an official weather forecast, "
            "evacuation order, or emergency alert."
        ),
    })
    return result


def _hurricane_push_text(result: dict) -> str:
    gap = float(result.get("potential_gap") or 0)
    if gap > 0:
        return f"Storm costs could leave you ${gap:.2f} short - see your plan......"
    cushion = float(result.get("remaining_cushion") or 0)
    return f"Your plan covers storm costs with ${cushion:.2f} left......"


async def run_daily_push_cycle(gateway_instance=None, sender=send_cashflow_warning):
    """Send each registered user at most one warning for today's forecast."""
    connection = db()
    try:
        owners = [row["owner"] for row in connection.execute(
            "SELECT DISTINCT owner FROM push_devices").fetchall()]
    finally:
        connection.close()

    gateway_instance = gateway_instance or getattr(app.state, "nessie", None) or NessieGateway()
    delivered = 0
    today = date.today().isoformat()
    for owner in owners:
        reminder_id = None
        try:
            profile = manifest(owner)
            account_values = await accounts(gateway_instance, profile)
            forecast_result = forecast_from(account_values, profile, days=7)
            if not forecast_result["is_shortfall"]:
                continue

            reminder_id = hashlib.sha256(
                (owner + "|cashflow-push|" + today).encode("utf-8")).hexdigest()
            connection = db()
            try:
                claimed = connection.execute(
                    "INSERT OR IGNORE INTO actions(id,owner,action_type,status,payload) "
                    "VALUES (?,?,?,?,?)",
                    (reminder_id, owner, "cashflow_push", "sending",
                     json.dumps({"date": today,
                                 "shortfall_amount": forecast_result["shortfall_amount"],
                                 "first_shortfall_date": forecast_result["first_shortfall_date"]}))).rowcount == 1
                tokens = [row["token"] for row in connection.execute(
                    "SELECT token FROM push_devices WHERE owner=?", (owner,)).fetchall()]
                connection.commit()
            finally:
                connection.close()
            if not claimed or not tokens:
                continue

            result = await asyncio.to_thread(
                sender, tokens, "CreditPilot cash warning",
                _cashflow_push_text(forecast_result))
            connection = db()
            try:
                for token in result.get("invalid_tokens", []):
                    connection.execute("DELETE FROM push_devices WHERE token=?", (token,))
                if result.get("success_count", 0) > 0:
                    connection.execute(
                        "UPDATE actions SET status='delivered' WHERE id=?", (reminder_id,))
                    delivered += 1
                else:
                    connection.execute("DELETE FROM actions WHERE id=?", (reminder_id,))
                connection.commit()
            finally:
                connection.close()
        except Exception:
            # One unavailable sandbox or bad device must not stop other users.
            if reminder_id is not None:
                connection = db()
                try:
                    connection.execute(
                        "DELETE FROM actions WHERE id=? AND status='sending'",
                        (reminder_id,))
                    connection.commit()
                finally:
                    connection.close()
            continue
    return {"users_notified": delivered}


async def run_hurricane_push_cycle(gateway_instance=None,
                                   sender=send_hurricane_warning):
    """Send one daily opt-in hurricane budget simulation per subscribed user."""
    connection = db()
    try:
        subscriptions = connection.execute(
            "SELECT owner,region,safety_buffer FROM hurricane_subscriptions "
            "WHERE enabled=1"
        ).fetchall()
    finally:
        connection.close()

    delivered = 0
    today = date.today().isoformat()
    for subscription in subscriptions:
        owner = subscription["owner"]
        reminder_id = hashlib.sha256(
            (owner + "|hurricane-simulation|" + today).encode("utf-8")
        ).hexdigest()
        try:
            result = await hurricane_assessment(
                owner, subscription["region"], subscription["safety_buffer"],
                gateway_instance,
            )
            connection = db()
            try:
                claimed = connection.execute(
                    "INSERT OR IGNORE INTO actions(id,owner,action_type,status,payload) "
                    "VALUES (?,?,?,?,?)",
                    (reminder_id, owner, "hurricane_simulation_push", "sending",
                     json.dumps({"date": today, "region": result["region"],
                                 "potential_gap": result["potential_gap"]})),
                ).rowcount == 1
                tokens = [row["token"] for row in connection.execute(
                    "SELECT token FROM push_devices WHERE owner=?", (owner,)
                ).fetchall()]
                connection.commit()
            finally:
                connection.close()
            if not claimed or not tokens:
                continue

            send_result = await asyncio.to_thread(
                sender, tokens, "Hurricane budget simulation",
                _hurricane_push_text(result),
            )
            connection = db()
            try:
                for token in send_result.get("invalid_tokens", []):
                    connection.execute("DELETE FROM push_devices WHERE token=?", (token,))
                if send_result.get("success_count", 0) > 0:
                    connection.execute(
                        "UPDATE actions SET status='delivered' WHERE id=?", (reminder_id,)
                    )
                    delivered += 1
                else:
                    connection.execute("DELETE FROM actions WHERE id=?", (reminder_id,))
                connection.commit()
            finally:
                connection.close()
        except Exception:
            connection = db()
            try:
                connection.execute(
                    "DELETE FROM actions WHERE id=? AND status='sending'", (reminder_id,)
                )
                connection.commit()
            finally:
                connection.close()
    return {"users_notified": delivered}


async def push_notification_loop():
    """Run the server-side daily check; disabled unless explicitly configured."""
    last_attempt = None
    while True:
        now = __import__("datetime").datetime.now()
        today = now.date().isoformat()
        if now.hour >= PUSH_DAILY_HOUR and last_attempt != today:
            last_attempt = today
            await run_daily_push_cycle()
            if HURRICANE_SIMULATION_ENABLED:
                await run_hurricane_push_cycle()
        await asyncio.sleep(60 * 15)


@app.get("/health")
def health():
    return {"status": "ok", "app": "CreditPilot", "auth_mode": AUTH_MODE,
            "data_mode": DATA_MODE, "demo_storage": DEMO_STORE,
            "payment_mode": PAYMENT_MODE,
            "seed_manifest_present": MANIFEST.is_file()}


@app.get("/api/dashboard")
async def dashboard(request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    f = forecast_from(a, m, days=7)
    return {"accounts": [
        {"kind": name, "id": item["_id"], "type": item.get("type"),
         "nickname": item.get("nickname"), "balance": account_amount(item),
         "institution": item.get("institution"), "last4": item.get("last4"),
         "currency": "USD", "credit_limit": item.get("credit_limit"),
         "source": m.get("source", "nessie_sandbox")}
        for name, item in a.items()],
        "bill_forecast": f, "data_sources": f["data_sources"]}


@app.post("/api/push/register")
def register_push_device(device: PushDeviceInput, user=Depends(actor)):
    connection = db()
    try:
        connection.execute(
            "INSERT INTO push_devices(token,owner,platform,updated_at) VALUES (?,?,?,CURRENT_TIMESTAMP) "
            "ON CONFLICT(token) DO UPDATE SET owner=excluded.owner, "
            "platform=excluded.platform, updated_at=CURRENT_TIMESTAMP",
            (device.token, user, device.platform))
        connection.commit()
    finally:
        connection.close()
    return {"registered": True}


@app.post("/api/push/unregister")
def unregister_push_device(device: PushDeviceInput, user=Depends(actor)):
    connection = db()
    try:
        removed = connection.execute(
            "DELETE FROM push_devices WHERE token=? AND owner=?",
            (device.token, user)).rowcount
        connection.commit()
    finally:
        connection.close()
    return {"unregistered": removed == 1}


@app.get("/api/accounts")
async def get_accounts(request: Request, user=Depends(actor)):
    return {"accounts": (await dashboard(request, user))["accounts"]}


@app.get("/api/bills")
def get_bills(user=Depends(actor)):
    m = manifest(user)
    upcoming = []
    for bill in bills(m):
        item = dict(bill)
        if item.get("frequency") == "monthly":
            item["payment_date"] = next_payment_date(item).isoformat()
            item["upcoming_payment_date"] = item["payment_date"]
        upcoming.append(item)
    return {"bills": upcoming, "source": m.get("source", "local_app_simulation")}


def require_synthetic():
    if DATA_MODE != "synthetic":
        raise HTTPException(409, "This feature requires automatic synthetic banking profiles")


@app.get("/api/demo/catalog")
def synthetic_catalog(user=Depends(actor)):
    require_synthetic()
    if using_tigerdata():
        return tiger_store().stats()
    connection = db()
    try:
        return demo_bank.stats(connection)
    finally:
        connection.close()


@app.get("/api/profile")
def my_banking_profile(user=Depends(actor)):
    m = manifest(user)
    return {
        "profile_id": m.get("portfolio_id"),
        "persona": m.get("persona", "legacy_demo"),
        "monthly_income": m.get("monthly_income"),
        "account_count": len(m["ids"]["accounts"]),
        "bill_count": len(m["app_bills"]),
        "source": m.get("source", "nessie_sandbox"),
        "simulation_only": True,
    }


class IncomeUpdate(BaseModel):
    monthly_income: float = Field(..., ge=0, le=1000000)


@app.post("/api/profile/income")
def update_demo_income(body: IncomeUpdate, user=Depends(actor)):
    require_synthetic()
    manifest(user)
    if using_tigerdata():
        return tiger_store().revise_income(user, body.monthly_income)
    connection = db()
    try:
        return demo_bank.revise_income(connection, user, body.monthly_income)
    finally:
        connection.close()


@app.get("/api/cards/catalog")
async def get_card_catalog(request: Request, user=Depends(actor)):
    m = manifest(user)
    data = await accounts(gateway(request), m)
    cards = []
    for key, rule in card_rules(m, data).items():
        cards.append({
            "account": key, "display_name": rule["display_name"],
            "issuer": rule["issuer"], "network": rule["network"],
            "last4": rule["last4"], "balance": rule["balance"],
            "credit_limit": rule["credit_limit"],
            "rewards": rule["reward_rates"],
            "visual_theme": rule["visual_theme"],
            "benefit_summary": rule["benefit_summary"],
            "source": m.get("source", "local_app_simulation"),
        })
    return {"cards": cards,
            "disclaimer": "Card issuers, product names and reward rates are fictional scenarios."}


@app.get("/api/transactions")
def get_demo_transactions(limit: int = 50, offset: int = 0, user=Depends(actor)):
    require_synthetic()
    if not 1 <= limit <= 100 or offset < 0:
        raise HTTPException(422, "Limit must be 1–100, offset must be nonnegative")
    m = manifest(user)
    if using_tigerdata():
        return tiger_store().transactions(user, limit, offset)
    records = m.get("transactions", [])
    return {"transactions": records[offset:offset+limit], "total": len(records),
            "limit": limit, "offset": offset, "source": demo_bank.DATA_SOURCE}


@app.get("/api/transactions/summary")
def get_spending_summary(days: int = 30, user=Depends(actor)):
    require_synthetic()
    if not 1 <= days <= 365:
        raise HTTPException(422, "Days must be between 1 and 365")
    m = manifest(user)
    if using_tigerdata():
        return tiger_store().spending_summary(user, days)
    # SQLite compatibility: the same output contract for SDK consumers.
    today = date.today()
    totals = {}
    for item in m.get("transactions", []):
        when = date.fromisoformat(str(item["date"])[:10])
        if (today - when).days not in range(days + 1):
            continue
        if item["direction"] != "debit" or item["category"] == "transfer":
            continue
        category = item["category"]
        row = totals.setdefault(category, {"category": category, "amount": 0.0, "count": 0})
        row["amount"] = round(row["amount"] + float(item["amount"]), 2)
        row["count"] += 1
    rows = sorted(totals.values(), key=lambda x: x["amount"], reverse=True)
    return {"period_days": days, "by_category": rows,
            "source": demo_bank.DATA_SOURCE, "storage": "sqlite"}


class DemoBillInput(BaseModel):
    payee: str = Field(..., min_length=2, max_length=100)
    payment_amount: float = Field(..., gt=0, le=100000)
    payment_date: date
    category: str = Field("other", min_length=2, max_length=40)
    frequency: str = Field("monthly", pattern="^(monthly|one_time)$")


@app.post("/api/bills/create")
def create_demo_bill(body: DemoBillInput, user=Depends(actor)):
    require_synthetic()
    manifest(user)
    if using_tigerdata():
        payload = body.model_dump()
        payload["payment_date"] = body.payment_date.isoformat()
        return {"bill": tiger_store().upsert_bill(user, payload)}
    connection = db()
    try:
        payload = body.model_dump()
        payload["payment_date"] = body.payment_date.isoformat()
        return {"bill": demo_bank.upsert_bill(connection, user, payload)}
    finally:
        connection.close()


@app.post("/api/bills/{bill_id}/update")
def update_demo_bill(bill_id: str, body: DemoBillInput, user=Depends(actor)):
    require_synthetic()
    manifest(user)
    if using_tigerdata():
        payload = body.model_dump()
        payload["payment_date"] = body.payment_date.isoformat()
        try:
            return {"bill": tiger_store().upsert_bill(user, payload, bill_id)}
        except ValueError:
            raise HTTPException(404, "Bill not found in this user's demo portfolio") from None
    connection = db()
    try:
        payload = body.model_dump()
        payload["payment_date"] = body.payment_date.isoformat()
        try:
            return {"bill": demo_bank.upsert_bill(connection, user, payload, bill_id)}
        except ValueError:
            raise HTTPException(404, "Bill was not found in your demo portfolio") from None
    finally:
        connection.close()


@app.post("/api/bills/{bill_id}/delete")
def delete_demo_bill(bill_id: str, user=Depends(actor)):
    require_synthetic()
    manifest(user)
    if using_tigerdata():
        try:
            tiger_store().delete_bill(user, bill_id)
        except ValueError:
            raise HTTPException(404, "Bill not found in this user's demo portfolio") from None
        return {"bill_id": bill_id, "status": "deleted_from_demo"}
    connection = db()
    try:
        try:
            demo_bank.delete_bill(connection, user, bill_id)
        except ValueError:
            raise HTTPException(404, "Bill was not found in your demo portfolio") from None
        return {"bill_id": bill_id, "status": "deleted_from_demo"}
    finally:
        connection.close()


class BillForecastRequest(BaseModel):
    horizon_days: int = Field(7, ge=1, le=90)
    protected_reserve: float = Field(0, ge=0)


@app.post("/api/bills/forecast")
async def bill_forecast(body: BillForecastRequest, request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    return forecast_from(a, m, body.horizon_days, body.protected_reserve)


class CardRequest(BaseModel):
    purchase_amount: float = Field(..., gt=0, le=100000)
    purchase_category: Literal[
        "groceries", "gas", "dining", "flights", "travel", "transit",
        "streaming", "shopping", "entertainment", "other"
    ] = "other"
    merchant_name: str = Field(..., min_length=1, max_length=90)
    utilization_target_pct: float = Field(30, ge=0, le=100)


class NearbyMerchantRequest(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    radius_m: int = Field(250, ge=50, le=2000)


@app.post("/api/locations/nearby")
async def locations_nearby(body: NearbyMerchantRequest, user=Depends(actor)):
    # Resolve authentication before forwarding coordinates. Coordinates are
    # used for this request only and are never written to application storage.
    del user
    if not GOOGLE_PLACES_API_KEY:
        return {
            "configured": False,
            "places": [],
            "message": "Nearby merchant lookup is not configured.",
        }
    try:
        places = await nearby_merchants(
            body.latitude, body.longitude, GOOGLE_PLACES_API_KEY, body.radius_m)
    except httpx.HTTPStatusError as error:
        status = error.response.status_code
        raise HTTPException(502, f"Nearby merchant provider returned HTTP {status}") from None
    except httpx.HTTPError:
        raise HTTPException(502, "Nearby merchant lookup is temporarily unavailable") from None
    return {
        "configured": True,
        "places": places,
        "location_retained": False,
    }


@app.post("/api/cards/evaluate")
async def cards_evaluate(body: CardRequest, request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    result = card_comparison(card_rules(m, a), body.purchase_amount,
                             body.purchase_category.lower(), body.utilization_target_pct)
    result["merchant_name"] = body.merchant_name
    result["data_sources"] = {
        "balances": m.get("source", "nessie_sandbox"),
        "rewards_and_limits": m.get("source", "local_app_simulation"),
    }
    return result


class AutopayRequest(BaseModel):
    target_utilization_pct: float = Field(29, ge=0, le=100)
    account: str = Field("card_1", pattern="^card_[a-zA-Z0-9]+$")
    safety_buffer: float = Field(100, ge=0)
    horizon_days: int = Field(14, ge=1, le=60)
    assumed_savings_transfer: float = Field(
        0, ge=0, description="What-if funding transfer; no money moves")
    savings_reserve: float = Field(200, ge=0)
    reminder_lead_days: int = Field(5, ge=1, le=14)
    payment_processing_days: int = Field(3, ge=1, le=7)
    notifications_enabled: bool = True
    adaptive_target: bool = True


async def calculate_autopay(body, g, user):
    m = manifest(user)
    a = await accounts(g, m)
    f = forecast_from(a, m, body.horizon_days)
    available_cards = card_rules(m, a)
    account_key = body.account
    if account_key == "card_1" and account_key not in available_cards and "card_a" in available_cards:
        account_key = "card_a"  # Legacy Nessie sample only.
    if account_key not in available_cards:
        raise HTTPException(422, "Unknown credit card for this signed-in user")
    rule = available_cards[account_key]
    x = m["app_scenario"][account_key]
    today = date.today()
    statement_date = today + timedelta(
        days=int(x.get("statement_closes_in_days", 9)))
    statement = statement_date.isoformat()
    transfer = money(body.assumed_savings_transfer)
    remaining_savings = money(account_amount(a["savings"])) - transfer
    if remaining_savings < money(body.savings_reserve):
        raise HTTPException(409, "What-if savings transfer would violate protected savings reserve")
    checking_for_plan = money(account_amount(a["checking"])) + transfer
    if body.adaptive_target:
        result = adaptive_autopay_preview(
            rule["balance"], rule["credit_limit"], checking_for_plan,
            f["total_bills_due"], body.safety_buffer, statement)
    else:
        result = autopay_preview(
            rule["balance"], rule["credit_limit"],
            body.target_utilization_pct, checking_for_plan,
            f["total_bills_due"], body.safety_buffer, statement)
        result["adaptive_target"] = False
        result["recommended_target_pct"] = body.target_utilization_pct
        result["target_status"] = "manual_target"
        result["target_options"] = []
        result["target_explanation"] = "The user selected this target manually."
    result["assumed_savings_transfer"] = amount(transfer)
    result["savings_after_assumed_transfer"] = amount(remaining_savings)
    result["is_what_if_scenario"] = transfer > 0
    result["account"] = account_key
    result["card_display_name"] = rule["display_name"]
    result["card_last4"] = rule["last4"]
    early_payment_date = max(
        today, statement_date - timedelta(days=body.payment_processing_days))
    reminder_date = max(
        today, early_payment_date - timedelta(days=body.reminder_lead_days))
    due_date = statement_date + timedelta(days=21)
    remaining_after_early = clamp_positive(
        money(rule["balance"]) - money(result["recommended_payment_amount"]))
    result["estimated_statement_close"] = statement
    result["estimated_reporting_window"] = {
        "start": statement,
        "end": (statement_date + timedelta(days=3)).isoformat(),
        "confidence": "estimated",
    }
    result["early_payment_date"] = early_payment_date.isoformat()
    result["estimated_payment_due_date"] = due_date.isoformat()
    result["remaining_balance_after_early_payment"] = amount(remaining_after_early)
    result["reminder_lead_days"] = body.reminder_lead_days
    result["payment_processing_days"] = body.payment_processing_days
    result["notifications_enabled"] = body.notifications_enabled
    early_amount = money(result["recommended_payment_amount"])
    selected_target = result.get("recommended_target_pct")
    early_message = (
        f"Review a ${early_amount} payment by {early_payment_date.isoformat()} "
        f"to target {selected_target:g}% utilization."
        if early_amount > 0 else
        f"Recheck the balance and available cash by {early_payment_date.isoformat()}; "
        "no affordable early payment is currently identified."
    )
    result["notification_plan"] = [
        {
            "type": "utilization_reminder",
            "date": reminder_date.isoformat(),
            "title": f"{rule['display_name']} utilization check",
            "message": early_message,
        },
        {
            "type": "early_payment_deadline",
            "date": early_payment_date.isoformat(),
            "title": "Early payment window",
            "message": (
                f"Payment processing may take {body.payment_processing_days} days. "
                "Confirm the issuer has posted any payment."
            ),
        },
        {
            "type": "statement_balance_due",
            "date": (due_date - timedelta(days=3)).isoformat(),
            "title": "Statement balance reminder",
            "message": (
                f"Review the statement balance before the estimated "
                f"{due_date.isoformat()} due date to help avoid interest."
            ),
        },
    ]
    result["timeline"] = [
        {
            "stage": "Early utilization payment",
            "date": early_payment_date.isoformat(),
            "amount": result["recommended_payment_amount"],
            "description": "Optional payment intended to lower the balance likely to be reported.",
        },
        {
            "stage": "Statement closes",
            "date": statement,
            "amount": None,
            "description": "Estimated billing-cycle close; issuer reporting may occur on another date.",
        },
        {
            "stage": "Statement balance due",
            "date": due_date.isoformat(),
            "amount": amount(remaining_after_early),
            "description": "Pay the actual statement balance shown by the issuer, not this estimate.",
        },
    ]
    result["data_sources"] = {
        "balances": m.get("source", "nessie_sandbox"),
        "credit_limit_and_statement": m.get("source", "local_app_simulation"),
    }
    return result


@app.post("/api/autopay/preview")
async def preview_autopay(body: AutopayRequest, request: Request, user=Depends(actor)):
    return await calculate_autopay(body, gateway(request), user)


def insert_action(identity, owner, typ, status, payload):
    connection = db()
    try:
        connection.execute("INSERT INTO actions(id, owner, action_type, status, payload) VALUES (?,?,?,?,?)",
                           (identity, owner, typ, status, json.dumps(payload)))
        connection.commit()
    finally:
        connection.close()


class AutopayPlanRequest(AutopayRequest):
    confirmed: bool


class PortfolioAutopayRequest(BaseModel):
    safety_buffer: float = Field(100, ge=0)
    savings_reserve: float = Field(1000, ge=0)
    include_available_savings: bool = False
    horizon_days: int = Field(14, ge=1, le=60)
    reminder_lead_days: int = Field(5, ge=1, le=14)
    payment_processing_days: int = Field(3, ge=1, le=7)
    notifications_enabled: bool = True


async def calculate_portfolio_autopay(body, g, user):
    m = manifest(user)
    account_values = await accounts(g, m)
    forecast = forecast_from(account_values, m, body.horizon_days)
    rules = card_rules(m, account_values)
    today = date.today()
    cards = []
    for key, rule in rules.items():
        scenario = m.get("app_scenario", {}).get(key, {})
        statement_date = today + timedelta(
            days=int(scenario.get("statement_closes_in_days", 9)))
        pay_by = max(
            today, statement_date - timedelta(days=body.payment_processing_days))
        cards.append({
            "account": key,
            "display_name": rule["display_name"],
            "last4": rule["last4"],
            "balance": rule["balance"],
            "credit_limit": rule["credit_limit"],
            "statement_date": statement_date.isoformat(),
            "pay_by_date": pay_by.isoformat(),
        })

    checking = money(account_amount(account_values["checking"]))
    savings = money(account_amount(account_values.get("savings", {})))
    savings_available = (
        clamp_positive(savings - money(body.savings_reserve))
        if body.include_available_savings else Decimal("0.00"))
    available_budget = clamp_positive(
        checking + savings_available - money(forecast["total_bills_due"])
        - money(body.safety_buffer))
    result = optimize_card_portfolio(cards, available_budget)
    result.update({
        "checking_balance": amount(checking),
        "savings_balance": amount(savings),
        "savings_included": body.include_available_savings,
        "savings_reserve": amount(body.savings_reserve),
        "upcoming_bills": forecast["total_bills_due"],
        "safety_buffer": amount(body.safety_buffer),
        "horizon_days": body.horizon_days,
        "notifications_enabled": body.notifications_enabled,
        "reporting_dates_are_estimates": True,
        "funding_explanation": (
            "Budget uses checking plus savings above the protected reserve, after "
            "upcoming bills and the safety buffer. No funds move automatically."
            if body.include_available_savings else
            "Budget uses checking after upcoming bills and the safety buffer."
        ),
    })
    reminders = []
    for card in result["cards"]:
        reminder_date = max(
            today,
            date.fromisoformat(card["pay_by_date"])
            - timedelta(days=body.reminder_lead_days),
        )
        payment = money(card["recommended_payment_amount"])
        reminders.append({
            "account": card["account"],
            "date": reminder_date.isoformat(),
            "title": f"{card['display_name']} statement check",
            "message": (
                f"Review a ${payment} payment by {card['pay_by_date']} before "
                "the estimated statement close."
                if payment > 0 else
                "Review this card before its estimated statement close; protected "
                "cash is currently allocated elsewhere."
            ),
        })
    result["notification_plan"] = reminders
    return result


@app.post("/api/autopay/portfolio-preview")
async def portfolio_autopay_preview(
        body: PortfolioAutopayRequest, request: Request, user=Depends(actor)):
    return await calculate_portfolio_autopay(body, gateway(request), user)


class PortfolioAutopayPlanRequest(PortfolioAutopayRequest):
    confirmed: bool


@app.post("/api/autopay/portfolio-plans")
async def plan_portfolio_autopay(
        body: PortfolioAutopayPlanRequest, request: Request, user=Depends(actor)):
    if not body.confirmed:
        raise HTTPException(400, "Explicit user confirmation required")
    preview = await calculate_portfolio_autopay(body, gateway(request), user)
    identity = str(uuid4())
    insert_action(
        identity, user, "portfolio_autopay_plan", "statement_guard_active", preview)
    return {
        "plan_id": identity,
        "status": "statement_guard_active",
        "allocated_payment_total": preview["allocated_payment_total"],
        "cards_monitored": len(preview["cards"]),
        "notification_plan": preview["notification_plan"],
        "device_push_configured": False,
        "execution": "NO BANK PAYMENT WILL OCCUR",
    }


@app.post("/api/autopay/plans")
async def plan_autopay(body: AutopayPlanRequest, request: Request, user=Depends(actor)):
    if not body.confirmed:
        raise HTTPException(400, "Explicit user confirmation required")
    preview = await calculate_autopay(body, gateway(request), user)
    identity = str(uuid4())
    insert_action(identity, user, "autopay_plan", "statement_guard_active", preview)
    return {"plan_id": identity, "status": "statement_guard_active",
            "payment_amount": preview["recommended_payment_amount"],
            "notification_plan": preview["notification_plan"],
            "device_push_configured": False,
            "execution": "NO BANK PAYMENT WILL OCCUR",
            "note": "Reminder dates are stored. Device push requires a configured notification provider; no payment is initiated."}


@app.get("/api/autopay/plans")
def list_autopay(user=Depends(actor)):
    connection = db()
    try:
        rows = connection.execute(
            "SELECT id, status, payload, created_at FROM actions WHERE owner=? AND action_type='autopay_plan'",
            (user,)).fetchall()
        return {"plans": [{"plan_id": r["id"], "status": r["status"],
                           "details": json.loads(r["payload"]), "created_at": r["created_at"]}
                          for r in rows]}
    finally:
        connection.close()


@app.post("/api/autopay/plans/{plan_id}/cancel")
def cancel_autopay(plan_id: str, user=Depends(actor)):
    connection = db()
    try:
        cursor = connection.execute(
            "UPDATE actions SET status='cancelled' WHERE id=? AND owner=? AND action_type='autopay_plan' AND status IN ('scheduled_simulation','statement_guard_active')",
            (plan_id, user))
        connection.commit()
        if not cursor.rowcount:
            raise HTTPException(404, "Plan not found or already cancelled")
        return {"plan_id": plan_id, "status": "cancelled"}
    finally:
        connection.close()


class EmergencyRequest(BaseModel):
    emergency_cost: float = Field(1000, ge=0, le=1000000)
    safety_buffer: float = Field(300, ge=0)
    horizon_days: int = Field(14, ge=1, le=90)


class HurricaneSubscriptionRequest(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    safety_buffer: float = Field(300, ge=0, le=100000)


@app.post("/api/emergency/evaluate")
async def evaluate_emergency(body: EmergencyRequest, request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    f = forecast_from(a, m, body.horizon_days)
    result = emergency(account_amount(a["checking"]), account_amount(a["savings"]),
                       f["total_bills_due"], body.emergency_cost, body.safety_buffer)
    result["data_sources"] = f["data_sources"]
    return result


@app.post("/api/emergency/hurricane/subscribe")
async def subscribe_hurricane_simulation(body: HurricaneSubscriptionRequest,
                                         request: Request,
                                         user=Depends(actor)):
    region = _hurricane_region(body.latitude, body.longitude)
    connection = db()
    try:
        connection.execute(
            "INSERT INTO hurricane_subscriptions(owner,region,safety_buffer,enabled,updated_at) "
            "VALUES (?,?,?,1,CURRENT_TIMESTAMP) ON CONFLICT(owner) DO UPDATE SET "
            "region=excluded.region,safety_buffer=excluded.safety_buffer,enabled=1,"
            "updated_at=CURRENT_TIMESTAMP",
            (user, region, body.safety_buffer),
        )
        connection.commit()
    finally:
        connection.close()
    result = await hurricane_assessment(
        user, region, body.safety_buffer, gateway(request)
    )
    result["alert_subscribed"] = True
    result["location_storage"] = "Broad region only; precise coordinates were discarded."
    return result


@app.get("/api/emergency/hurricane")
async def get_hurricane_simulation(request: Request, user=Depends(actor)):
    connection = db()
    try:
        subscription = connection.execute(
            "SELECT region,safety_buffer FROM hurricane_subscriptions "
            "WHERE owner=? AND enabled=1", (user,)
        ).fetchone()
    finally:
        connection.close()
    if not subscription:
        return {"alert_subscribed": False}
    result = await hurricane_assessment(
        user, subscription["region"], subscription["safety_buffer"],
        gateway(request),
    )
    result["alert_subscribed"] = True
    result["location_storage"] = "Broad region only; precise coordinates were discarded."
    return result


@app.post("/api/emergency/hurricane/unsubscribe")
def unsubscribe_hurricane_simulation(user=Depends(actor)):
    connection = db()
    try:
        changed = connection.execute(
            "UPDATE hurricane_subscriptions SET enabled=0,updated_at=CURRENT_TIMESTAMP "
            "WHERE owner=?", (user,)
        ).rowcount
        connection.commit()
    finally:
        connection.close()
    return {"alert_subscribed": False, "changed": changed == 1}


# Legacy partner routes are intentionally removed: only verified membership and
# primary/dependent roles authorize the joint payment workflow.
from joint_accounts import create_router as joint_router
app.include_router(joint_router(db, actor, gateway, lambda:
    AUTH_MODE == "auth0" and DATA_MODE == "nessie" and PAYMENT_MODE == "nessie"))


class TransferRequest(BaseModel):
    amount: float = Field(..., gt=0, le=100000)
    idempotency_key: str = Field(..., min_length=8, max_length=100)
    confirmed: bool = False
    savings_reserve: float = Field(200, ge=0)


@app.post("/api/transfers/preview")
async def preview_transfer(body: TransferRequest, request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    balance = account_amount(a["savings"])
    max_safe = max(0, amount(balance - body.savings_reserve))
    return {"amount": body.amount, "source": "savings", "destination": "checking",
            "available_savings": balance, "protected_savings": body.savings_reserve,
            "max_safe_transfer": max_safe, "allowed": money(body.amount) <= money(max_safe),
            "execution": "synthetic_simulation" if DATA_MODE == "synthetic"
                else ("simulated" if PAYMENT_MODE == "simulate" else "Nessie sandbox only")}


@app.post("/api/transfers/execute")
async def execute_transfer(body: TransferRequest, request: Request, user=Depends(actor)):
    if not body.confirmed:
        raise HTTPException(400, "User must explicitly confirm this transfer")
    if DATA_MODE == "synthetic":
        if PAYMENT_MODE != "simulate":
            raise HTTPException(409, "Synthetic banking supports simulation-only transfers")
        manifest(user)
        if using_tigerdata():
            try:
                return tiger_store().simulated_transfer(
                    user, body.amount, body.idempotency_key, body.savings_reserve)
            except ValueError:
                raise HTTPException(409, "Simulated transfer rejected") from None
        connection = db()
        try:
            try:
                return demo_bank.simulated_transfer(
                    connection, user, body.amount, body.idempotency_key,
                    body.savings_reserve)
            except ValueError as exc:
                raise HTTPException(409, str(exc)) from None
        finally:
            connection.close()
    if PAYMENT_MODE == "nessie" and user != os.getenv("NESSIE_TRANSFER_ALLOWED_SUB", ""):
        raise HTTPException(403, "Sandbox transfer execution not authorized for this user")
    # A unique idempotency key is reserved before any Nessie write; unknown outcomes
    # never auto-retry. A reconciliation process is needed for production.
    connection = db()
    try:
        prior = connection.execute("SELECT * FROM actions WHERE id=?",
                                   (body.idempotency_key,)).fetchone()
        if prior:
            if prior["owner"] != user or prior["action_type"] != "transfer":
                raise HTTPException(409, "Idempotency key already used")
            p = json.loads(prior["payload"])
            if money(p["amount"]) != money(body.amount):
                raise HTTPException(409, "Idempotency key conflicts with amount")
            return {"idempotency_key": body.idempotency_key, "status": prior["status"],
                    "previous_request": True}
        preview = await preview_transfer(body, request, user)
        if not preview["allowed"]:
            raise HTTPException(409, "Transfer would exceed savings after protected reserve")
        connection.execute("INSERT INTO actions(id, owner, action_type, status, payload) VALUES(?,?,?,?,?)",
                           (body.idempotency_key, user, "transfer", "processing",
                            json.dumps({"amount": body.amount})))
        connection.commit()
    finally:
        connection.close()

    if PAYMENT_MODE == "simulate":
        outcome = "simulated_only"
    else:
        try:
            m = manifest(user)
            ids = m["ids"]["accounts"]
            # The documented Nessie payer-path / payee_id contract is used.
            await gateway(request).transfer(ids["savings"], ids["checking"], body.amount)
            outcome = "submitted_to_nessie_sandbox"
        except Exception:
            connection = db()
            try:
                connection.execute("UPDATE actions SET status='unknown_needs_reconciliation' WHERE id=?",
                                   (body.idempotency_key,))
                connection.commit()
            finally:
                connection.close()
            raise HTTPException(502, "Nessie transfer outcome unknown; do not retry with a new key") from None
    connection = db()
    try:
        connection.execute("UPDATE actions SET status=? WHERE id=?",
                           (outcome, body.idempotency_key))
        connection.commit()
    finally:
        connection.close()
    return {"idempotency_key": body.idempotency_key, "status": outcome,
            "simulation": PAYMENT_MODE == "simulate"}


class PurchaseDecision(CardRequest):
    emergency_cost: Optional[float] = Field(None, ge=0)


@app.post("/api/decisions/purchase")
async def integrated_decision(body: PurchaseDecision, request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    cards = card_comparison(card_rules(m, a), body.purchase_amount,
                            body.purchase_category.lower(), body.utilization_target_pct)
    f = forecast_from(a, m)
    guidance = purchase_guidance(cards, f)
    result = {"decision": "purchase_simulation", "card_options": cards,
              "cashflow_before_purchase": f,
              "recommended_card": cards["recommended_card"],
              "purchase_guidance": guidance,
              "note": "Credit-card purchases add future repayment obligations; an immediate checking debit does not occur."}
    if body.emergency_cost is not None:
        result["emergency_stress_test"] = emergency(
            account_amount(a["checking"]), account_amount(a["savings"]),
            f["total_bills_due"], body.emergency_cost, 300)
    return result


class TripChatTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(..., min_length=1, max_length=1800)


class TripCopilotRequest(BaseModel):
    message: str = Field(..., min_length=2, max_length=1500)
    history: list[TripChatTurn] = Field(default_factory=list, max_length=8)
    utilization_target_pct: float = Field(30, ge=1, le=100)


@app.post("/api/cards/copilot/plan")
async def cards_trip_copilot(body: TripCopilotRequest, request: Request,
                             user=Depends(actor)):
    """Parse trip intent with Gemini, then calculate every recommendation locally."""
    parsed, parse_error = await extract_trip_plan(
        body.message.strip(), [turn.model_dump() for turn in body.history])
    if parsed is None:
        return {
            "assistant_message": parse_error,
            "ai_used": False,
            "recommendations": [],
            "calculation_source": "deterministic_backend",
        }

    raw_purchases = parsed.get("purchases", [])
    if not isinstance(raw_purchases, list):
        raw_purchases = []
    valid_categories = {
        "groceries", "gas", "dining", "flights", "travel", "transit",
        "streaming", "shopping", "entertainment", "other",
    }
    purchases = []
    for item in raw_purchases[:12]:
        if not isinstance(item, dict):
            continue
        try:
            purchase_amount = float(item.get("amount", 0))
        except (TypeError, ValueError):
            continue
        category = str(item.get("category", "other")).lower()
        purpose = str(item.get("merchant_or_purpose", "Trip purchase")).strip()[:90]
        if (not purpose or category not in valid_categories
                or purchase_amount <= 0 or purchase_amount > 100000):
            continue
        purchases.append({
            "merchant_or_purpose": purpose,
            "category": category,
            "amount": round(purchase_amount, 2),
        })

    m = manifest(user)
    a = await accounts(gateway(request), m)
    working_rules = card_rules(m, a)
    cashflow = forecast_from(a, m)
    recommendations = []
    total_rewards = 0.0
    # Planned purchases are evaluated cumulatively. Once a card is selected,
    # its simulated balance increases before the next trip item is ranked.
    for purchase in purchases:
        comparison = card_comparison(
            working_rules, purchase["amount"], purchase["category"],
            body.utilization_target_pct)
        guidance = purchase_guidance(comparison, cashflow)
        best = comparison.get("recommended_card")
        if best:
            total_rewards += float(best.get("rewards_amount", 0))
            selected = working_rules.get(best["card_name"])
            if selected is not None:
                selected["balance"] = round(
                    float(selected.get("balance", 0)) + purchase["amount"], 2)
        recommendations.append({
            **purchase,
            "recommended_card": best,
            "verdict": guidance.get("verdict"),
            "headline": guidance.get("headline"),
            "timing_advice": guidance.get("timing_advice"),
            "alternatives": comparison.get("cards", [])[1:3],
        })

    missing = parsed.get("missing_information", [])
    if not isinstance(missing, list):
        missing = []
    safe_missing = [str(item)[:180] for item in missing[:5] if str(item).strip()]
    total_spend = round(sum(item["amount"] for item in purchases), 2)
    return {
        "trip_title": str(parsed.get("trip_title", "Trip plan"))[:90],
        "assistant_message": str(parsed.get("assistant_message", ""))[:500],
        "missing_information": safe_missing,
        "recommendations": recommendations,
        "summary": {
            "planned_spend": total_spend,
            "estimated_rewards": round(total_rewards, 2),
            "purchase_count": len(recommendations),
        },
        "ai_used": True,
        "calculation_source": "deterministic_backend",
        "bank_data_source": m.get("source", "nessie_sandbox"),
        "disclaimer": (
            "Planning estimate only. Confirm merchant categories and issuer terms; "
            "no purchase or payment was initiated."
        ),
    }


# Personalized AI agent. Gemini never owns balances or long-term storage.
# Memory is strictly opt-in, keyed by the Auth0-verified subject only.
class MemoryConsent(BaseModel):
    enabled: bool


class MemoryNote(BaseModel):
    note: str = Field(..., min_length=3, max_length=350)


class AgentChatRequest(BaseModel):
    message: str = Field(..., min_length=2, max_length=1300)


@app.get("/api/agent/settings")
def ai_memory_settings(user=Depends(actor)):
    repo = agent_memory()
    enabled = repo.enabled(user)
    return {"memory_enabled": enabled, "storage": repo.mode,
            "note_count": len(repo.memories(user)) if enabled else 0,
            "user_can_delete": True,
            "source_of_banking_balances": "nessie_sandbox" if DATA_MODE == "nessie" else demo_bank.DATA_SOURCE}


@app.post("/api/agent/settings")
def ai_memory_consent(body: MemoryConsent, user=Depends(actor)):
    return agent_memory().set_enabled(user, body.enabled)


@app.get("/api/agent/memories")
def ai_get_memories(user=Depends(actor)):
    repo = agent_memory()
    return {"memory_enabled": repo.enabled(user), "memories": repo.memories(user)}


@app.post("/api/agent/memories")
def ai_save_memory(body: MemoryNote, user=Depends(actor)):
    try:
        item = agent_memory().remember(user, str(uuid4()), body.note.strip())
        return {"memory": item, "saved": True}
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from None


@app.post("/api/agent/memories/{memory_id}/delete")
def ai_delete_memory(memory_id: str, user=Depends(actor)):
    if len(memory_id) > 100:
        raise HTTPException(422, "Invalid memory id")
    removed = agent_memory().remove(user, memory_id)
    if not removed:
        raise HTTPException(404, "Memory not found for this account")
    return {"deleted": True}


@app.post("/api/agent/memories/clear")
def ai_clear_memory(user=Depends(actor)):
    return agent_memory().clear(user)


@app.get("/api/agent/history")
def ai_history(user=Depends(actor)):
    repo = agent_memory()
    return {"memory_enabled": repo.enabled(user), "history": repo.history(user)}


@app.post("/api/agent/chat")
async def ai_agent_chat(body: AgentChatRequest, request: Request, user=Depends(actor)):
    # Never accept balances, accounts, customer IDs or memory owner in the
    # request body. Fetch the user's own authorized sandbox accounts directly.
    m = manifest(user)
    a = await accounts(gateway(request), m)
    verified_context = agent_snapshot(a, m, forecast_from(a, m), card_rules(m, a))
    repo = agent_memory()
    opted_in = repo.enabled(user)
    history = repo.history(user) if opted_in else []
    notes = repo.memories(user) if opted_in else []
    response, ai_used = await ask_gemini(
        body.message.strip(), verified_context, notes, history)
    if ai_used and opted_in:
        # Store only authenticated user's messages. Disable/delete revokes.
        repo.append(user, "user", body.message.strip())
        repo.append(user, "assistant", response)
    return {"response": response, "ai_used": ai_used,
            "memory_enabled": opted_in, "bank_data_source": verified_context["source"],
            "banking_is_sandbox": True, "context_source": "server_verified"}


class ExplainRequest(BaseModel):
    topic: str = Field(..., max_length=80)
    result: dict[str, Any]


@app.post("/api/ai/explain")
async def explain(body: ExplainRequest, user=Depends(actor)):
    # Explanations are generated solely from an already-calculated numeric result.
    # No PII, Nessie ID or other user's record is sent to Gemini.
    # Never forward user-provided names, account IDs or arbitrary nested
    # objects to an external model. Only approved numeric outcomes are sent.
    allowed = {
        "checking_balance", "savings_balance", "total_bills_due",
        "shortfall_amount", "suggested_savings_transfer",
        "projected_end_balance", "current_utilization_pct",
        "target_utilization_pct", "recommended_payment_amount",
        "max_safe_payment_today", "potential_gap", "usable_cash_buffer",
        "estimated_emergency_cost", "rewards_amount", "utilization_after_pct",
    }
    slim = {
        k: round(float(v), 2) for k, v in body.result.items()
        if k in allowed and isinstance(v, (int, float))
        and not isinstance(v, bool) and abs(float(v)) <= 100000000
    }
    fixed = "This is a simulated planning estimate, not a guaranteed financial outcome."
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        return {"text": fixed, "ai_used": False, "reason": "GEMINI_API_KEY not configured"}
    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    prompt = ("Explain this fictional banking scenario in no more than 75 plain-English "
              "words. Never invent amounts, dates, credit-score effects or bank powers. "
              "Numbers are generated by a deterministic engine. "
              "Scenario: " + body.topic + "\nData: " + json.dumps(slim)[:4500])
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.post(
                "https://generativelanguage.googleapis.com/v1beta/models/" +
                model + ":generateContent",
                headers={"x-goog-api-key": key, "Content-Type": "application/json"},
                json={"contents": [{"parts": [{"text": prompt}]}],
                      "generationConfig": {"temperature": 0.2, "maxOutputTokens": 160}})
            r.raise_for_status()
            candidates = r.json().get("candidates") or []
            parts = candidates[0].get("content", {}).get("parts", []) if candidates else []
            result = " ".join(str(p.get("text", "")) for p in parts).strip()
            return {"text": result or fixed, "ai_used": bool(result)}
    except (httpx.HTTPError, ValueError, KeyError):
        return {"text": fixed, "ai_used": False, "reason": "Gemini currently unavailable"}
