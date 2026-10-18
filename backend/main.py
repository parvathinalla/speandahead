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
from typing import Any, Optional
from uuid import uuid4

import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import jwt

from finance_engine import (
    amount, autopay_preview, card_comparison, emergency, forecast, joint_risk, money
)

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")
NESSIE_URL = os.getenv("NESSIE_BASE_URL", "https://prod-api.nessieisreal.com").rstrip("/")
MANIFEST = Path(os.getenv("SEED_MANIFEST_PATH", str(ROOT / "seed_manifest.json")))
SQLITE = Path(os.getenv("DB_PATH", str(ROOT / "creditpilot.sqlite3")))
AUTH_MODE = os.getenv("AUTH_MODE", "demo").strip().lower()
ENVIRONMENT = os.getenv("APP_ENV", "development").strip().lower()
TENANTS_DIR = Path(os.getenv("TENANT_MANIFEST_DIR", str(ROOT / "private" / "tenants")))
PAYMENT_MODE = os.getenv("PAYMENT_MODE", "simulate").strip().lower()
ORIGINS = [o.strip() for o in os.getenv("CORS_ORIGINS", "http://localhost:3000,http://localhost:8080,http://127.0.0.1:8080").split(",") if o.strip()]

if AUTH_MODE not in ("demo", "auth0"):
    raise RuntimeError("AUTH_MODE must be demo or auth0")
if PAYMENT_MODE not in ("simulate", "nessie"):
    raise RuntimeError("PAYMENT_MODE must be simulate or nessie")
if PAYMENT_MODE == "nessie" and AUTH_MODE == "demo":
    raise RuntimeError("Nessie transfer execution requires AUTH_MODE=auth0; demo stays simulation-only")
if ENVIRONMENT not in ("development", "test", "production"):
    raise RuntimeError("APP_ENV must be development, test, or production")
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


def db():
    SQLITE.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(SQLITE), timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("""CREATE TABLE IF NOT EXISTS actions (
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, action_type TEXT NOT NULL,
        status TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )""")
    conn.commit()
    return conn


@app.on_event("startup")
def init_db():
    connection = db()
    connection.close()


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
    except Exception:
        raise HTTPException(401, "Invalid or expired authentication token") from None


@app.get("/api/me")
def me(user=Depends(actor)):
    linked = has_linked_sandbox(user)
    return {"authenticated": True, "user_id": user,
            "sandbox_linked": linked, "onboarding_required": not linked,
            "security_mode": AUTH_MODE,
            "data_source": "fictional_nessie_sandbox"}


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
        names = ("checking", "savings", "card_a", "card_b", "joint_demo", "partner_checking")
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
    ids = m["ids"]["accounts"]
    if isinstance(g, NessieGateway):
        return await g.account_snapshot(ids)
    # Keep injected test adapters simple; they need only expose account(id).
    names = ("checking", "savings", "card_a", "card_b", "joint_demo", "partner_checking")
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
    for name in ("card_a", "card_b"):
        x = meta.get(name)
        if not x or not x.get("limit_usd"):
            raise HTTPException(503, "Missing simulated credit limit or rewards rules")
        rules[name] = {
            "account_id": account_values[name]["_id"],
            "balance": account_amount(account_values[name]),
            "credit_limit": x["limit_usd"],
            "reward_rates": x.get("rewards", {}),
        }
    return rules


def bills(m: dict):
    return list(m["app_bills"].values())


def forecast_from(a, m, days=14, reserve=0):
    result = forecast(account_amount(a["checking"]), account_amount(a["savings"]),
                      bills(m), days, reserve)
    result["data_sources"] = {"balances": "nessie_sandbox",
                              "bills": "local_app_simulation"}
    return result


@app.get("/health")
def health():
    return {"status": "ok", "app": "CreditPilot", "auth_mode": AUTH_MODE,
            "payment_mode": PAYMENT_MODE, "seed_manifest_present": MANIFEST.is_file()}


@app.get("/api/dashboard")
async def dashboard(request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    f = forecast_from(a, m)
    return {"accounts": [
        {"kind": name, "id": item["_id"], "type": item.get("type"),
         "nickname": item.get("nickname"), "balance": account_amount(item),
         "source": "nessie_sandbox"}
        for name, item in a.items()],
        "bill_forecast": f, "data_sources": f["data_sources"]}


@app.get("/api/accounts")
async def get_accounts(request: Request, user=Depends(actor)):
    return {"accounts": (await dashboard(request, user))["accounts"]}


@app.get("/api/bills")
def get_bills(user=Depends(actor)):
    return {"bills": bills(manifest(user)), "source": "local_app_simulation"}


class BillForecastRequest(BaseModel):
    horizon_days: int = Field(14, ge=1, le=90)
    protected_reserve: float = Field(0, ge=0)


@app.post("/api/bills/forecast")
async def bill_forecast(body: BillForecastRequest, request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    return forecast_from(a, m, body.horizon_days, body.protected_reserve)


class CardRequest(BaseModel):
    purchase_amount: float = Field(..., gt=0, le=100000)
    purchase_category: str = Field("groceries", max_length=40)
    merchant_name: str = Field("Demo merchant", max_length=90)
    utilization_target_pct: float = Field(30, ge=0, le=100)


@app.post("/api/cards/evaluate")
async def cards_evaluate(body: CardRequest, request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    result = card_comparison(card_rules(m, a), body.purchase_amount,
                             body.purchase_category.lower(), body.utilization_target_pct)
    result["merchant_name"] = body.merchant_name
    result["data_sources"] = {"balances": "nessie_sandbox",
                              "rewards_and_limits": "local_app_simulation"}
    return result


class AutopayRequest(BaseModel):
    target_utilization_pct: float = Field(29, ge=0, le=100)
    account: str = Field("card_a", pattern="^(card_a|card_b)$")
    safety_buffer: float = Field(100, ge=0)
    horizon_days: int = Field(14, ge=1, le=60)
    assumed_savings_transfer: float = Field(
        0, ge=0, description="What-if funding transfer; no money moves")
    savings_reserve: float = Field(200, ge=0)


async def calculate_autopay(body, g, user):
    m = manifest(user)
    a = await accounts(g, m)
    f = forecast_from(a, m, body.horizon_days)
    rule = card_rules(m, a)[body.account]
    x = m["app_scenario"][body.account]
    statement = (date.today() + timedelta(days=int(x.get("statement_closes_in_days", 9)))).isoformat()
    transfer = money(body.assumed_savings_transfer)
    remaining_savings = money(account_amount(a["savings"])) - transfer
    if remaining_savings < money(body.savings_reserve):
        raise HTTPException(409, "What-if savings transfer would violate protected savings reserve")
    checking_for_plan = money(account_amount(a["checking"])) + transfer
    result = autopay_preview(rule["balance"], rule["credit_limit"],
                             body.target_utilization_pct,
                             checking_for_plan, f["total_bills_due"],
                             body.safety_buffer, statement)
    result["assumed_savings_transfer"] = amount(transfer)
    result["savings_after_assumed_transfer"] = amount(remaining_savings)
    result["is_what_if_scenario"] = transfer > 0
    result["account"] = body.account
    result["data_sources"] = {"balances": "nessie_sandbox",
                              "credit_limit_and_statement": "local_app_simulation"}
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


@app.post("/api/autopay/plans")
async def plan_autopay(body: AutopayPlanRequest, request: Request, user=Depends(actor)):
    if not body.confirmed:
        raise HTTPException(400, "Explicit user confirmation required")
    preview = await calculate_autopay(body, gateway(request), user)
    if preview["recommended_payment_amount"] <= 0:
        raise HTTPException(409, "No affordable payment to schedule")
    identity = str(uuid4())
    insert_action(identity, user, "autopay_plan", "scheduled_simulation", preview)
    return {"plan_id": identity, "status": "scheduled_simulation",
            "payment_amount": preview["recommended_payment_amount"],
            "execution": "NO BANK PAYMENT WILL OCCUR",
            "note": "This stores a plan; it is not a credit bureau or issuer autopay integration."}


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
            "UPDATE actions SET status='cancelled' WHERE id=? AND owner=? AND action_type='autopay_plan' AND status='scheduled_simulation'",
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


@app.post("/api/emergency/evaluate")
async def evaluate_emergency(body: EmergencyRequest, request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    f = forecast_from(a, m, body.horizon_days)
    result = emergency(account_amount(a["checking"]), account_amount(a["savings"]),
                       f["total_bills_due"], body.emergency_cost, body.safety_buffer)
    result["data_sources"] = f["data_sources"]
    return result


class JointRequest(BaseModel):
    amount: float = Field(850, gt=0)
    merchant: str = Field("Electronics store", max_length=90)
    category: str = Field("Shopping", max_length=70)


@app.post("/api/joint/evaluate")
async def evaluate_joint(body: JointRequest, request: Request, user=Depends(actor)):
    m = manifest(user)
    a = await accounts(gateway(request), m)
    result = joint_risk(body.amount, account_amount(a["joint_demo"]))
    result.update({"merchant": body.merchant, "category": body.category,
                   "account_name": a["joint_demo"].get("nickname"),
                   "partner_name": "Jamie (simulated)",
                   "transaction_status": "NOT SUBMITTED",
                   "data_sources": {"balance": "nessie_sandbox",
                                    "threshold_and_partner": "app_simulation"}})
    return result


class JointProposal(JointRequest):
    confirmed: bool = False


@app.post("/api/joint/proposals")
async def propose_joint(body: JointProposal, request: Request, user=Depends(actor)):
    if not body.confirmed:
        raise HTTPException(400, "Initiator confirmation required")
    evaluation = await evaluate_joint(body, request, user)
    identity = str(uuid4())
    tenant = manifest(user)
    assigned_partner = ("demo-jamie" if AUTH_MODE == "demo"
                        else tenant.get("joint_partner_sub", ""))
    if not assigned_partner or assigned_partner == user:
        raise HTTPException(409, "Invite a verified partner before requesting approval")
    payload = {"initiator": user, "partner_sub": assigned_partner,
               "evaluation": evaluation}
    insert_action(identity, user, "joint_proposal", "awaiting_partner", payload)
    return {"proposal_id": identity, "status": "awaiting_partner",
            "note": "APP-SIMULATED approval, not a bank authorization hold"}


class JointDecision(BaseModel):
    approve: bool


@app.post("/api/joint/proposals/{proposal_id}/decision")
def joint_decision(proposal_id: str, body: JointDecision, user=Depends(actor)):
    connection = db()
    try:
        connection.execute("BEGIN IMMEDIATE")
        row = connection.execute("SELECT * FROM actions WHERE id=? AND action_type='joint_proposal'",
                                 (proposal_id,)).fetchone()
        if not row:
            raise HTTPException(404, "Unknown proposal")
        if row["owner"] == user:
            raise HTTPException(403, "Initiator cannot approve their own joint proposal")
        if user != json.loads(row["payload"]).get("partner_sub"):
            raise HTTPException(403, "Only the invited partner can approve")
        if row["status"] != "awaiting_partner":
            raise HTTPException(409, "Proposal already decided")
        # In demo mode the second demo identity models partner consent; real ownership
        # must be checked against a verified joint-account relationship in production.
        status = "approved_simulation" if body.approve else "declined"
        connection.execute("UPDATE actions SET status=? WHERE id=?", (status, proposal_id))
        connection.commit()
        return {"proposal_id": proposal_id, "status": status,
                "note": "No Nessie transaction was executed"}
    finally:
        connection.close()


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
            "execution": "simulated" if PAYMENT_MODE == "simulate" else "Nessie sandbox only"}


@app.post("/api/transfers/execute")
async def execute_transfer(body: TransferRequest, request: Request, user=Depends(actor)):
    if not body.confirmed:
        raise HTTPException(400, "User must explicitly confirm this transfer")
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
    result = {"decision": "purchase_simulation", "card_options": cards,
              "cashflow_before_purchase": f,
              "recommended_card": cards["recommended_card"],
              "note": "Credit-card purchases add future repayment obligations; an immediate checking debit does not occur."}
    if body.emergency_cost is not None:
        result["emergency_stress_test"] = emergency(
            account_amount(a["checking"]), account_amount(a["savings"]),
            f["total_bills_due"], body.emergency_cost, 300)
    return result


class ExplainRequest(BaseModel):
    topic: str = Field(..., max_length=80)
    result: dict[str, Any]


@app.post("/api/ai/explain")
async def explain(body: ExplainRequest, user=Depends(actor)):
    # Explanations are generated solely from an already-calculated numeric result.
    # No PII, Nessie ID or other user's record is sent to Gemini.
    slim = {k: v for k, v in body.result.items()
            if k not in ("accounts", "customer", "account_id", "id", "token", "api_key")}
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
