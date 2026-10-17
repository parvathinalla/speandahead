"""CreditPilot API: real Nessie accounts + explicit simulated financial scenarios.

Run: uvicorn main:app --app-dir backend --reload
Never place Nessie or Gemini API keys in Flutter or GitHub.
"""
import asyncio
from datetime import date, timedelta
from decimal import Decimal
import json
import os
from pathlib import Path
import sqlite3
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
PAYMENT_MODE = os.getenv("PAYMENT_MODE", "simulate").strip().lower()
ORIGINS = os.getenv("CORS_ORIGINS", "http://localhost:3000,http://localhost:8080,http://127.0.0.1:8080").split(",")

if AUTH_MODE not in ("demo", "auth0"):
    raise RuntimeError("AUTH_MODE must be demo or auth0")
if PAYMENT_MODE not in ("simulate", "nessie"):
    raise RuntimeError("PAYMENT_MODE must be simulate or nessie")
if PAYMENT_MODE == "nessie" and AUTH_MODE == "demo":
    raise RuntimeError("Nessie transfer execution requires AUTH_MODE=auth0; demo stays simulation-only")

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


def manifest() -> dict:
    if not MANIFEST.is_file():
        raise HTTPException(503, "Missing seed_manifest.json; run backend/scripts/seed_nessie.py --apply first")
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if not data.get("ids", {}).get("accounts"):
        raise HTTPException(503, "Seed manifest has no accounts")
    if not data.get("app_bills"):
        raise HTTPException(503, "No app-only bill forecast data; rerun latest seed script --apply")
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
        jwks = jwt.PyJWKClient("https://" + domain + "/.well-known/jwks.json", timeout=5)
        signing_key = await asyncio.to_thread(jwks.get_signing_key_from_jwt, token)
        claims = jwt.decode(token, signing_key.key, algorithms=["RS256"],
                            audience=audience, issuer="https://" + domain + "/",
                            options={"require": ["exp", "iss", "sub"]})
        return str(claims["sub"])
    except Exception:
        raise HTTPException(401, "Invalid or expired authentication token") from None


class NessieGateway:
    async def request(self, method: str, path: str, payload=None):
        key = os.getenv("NESSIE_API_KEY", "")
        if not key:
            raise HTTPException(503, "NESSIE_API_KEY missing on backend")
        if not NESSIE_URL.startswith("https://"):
            raise HTTPException(503, "Nessie URL must use HTTPS")
        try:
            async with httpx.AsyncClient(timeout=12) as client:
                response = await client.request(method, NESSIE_URL + path,
                                                params={"key": key}, json=payload)
                response.raise_for_status()
                if not response.content:
                    return {}
                return response.json()
        except httpx.HTTPStatusError as exc:
            # Do not leak Nessie URLs: the key is in their query strings.
            raise HTTPException(502, "Nessie returned HTTP " + str(exc.response.status_code)) from None
        except (httpx.RequestError, ValueError):
            raise HTTPException(502, "Nessie service unavailable or invalid response") from None

    async def account(self, account_id):
        return await self.request("GET", "/accounts/" + account_id)

    async def transfer(self, payer_id, payee_id, value):
        return await self.request("POST", "/accounts/" + payer_id + "/transfers",
                                  {"medium": "balance", "payee_id": payee_id,
                                   "amount": value, "transaction_date": date.today().isoformat(),
                                   "description": "CreditPilot user-approved sandbox transfer"})


def gateway(request: Request):
    return getattr(request.app.state, "nessie", None) or NessieGateway()


async def accounts(g: NessieGateway, m: dict) -> dict:
    ids = m["ids"]["accounts"]
    names = ["checking", "savings", "card_a", "card_b", "joint_demo", "partner_checking"]
    records = await asyncio.gather(*(g.account(ids[n]) for n in names))
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
    m = manifest()
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
    return {"bills": bills(manifest()), "source": "local_app_simulation"}


class BillForecastRequest(BaseModel):
    horizon_days: int = Field(14, ge=1, le=90)
    protected_reserve: float = Field(0, ge=0)


@app.post("/api/bills/forecast")
async def bill_forecast(body: BillForecastRequest, request: Request, user=Depends(actor)):
    m = manifest()
    a = await accounts(gateway(request), m)
    return forecast_from(a, m, body.horizon_days, body.protected_reserve)


class CardRequest(BaseModel):
    purchase_amount: float = Field(..., gt=0, le=100000)
    purchase_category: str = Field("groceries", max_length=40)
    merchant_name: str = Field("Demo merchant", max_length=90)
    utilization_target_pct: float = Field(30, ge=0, le=100)


@app.post("/api/cards/evaluate")
async def cards_evaluate(body: CardRequest, request: Request, user=Depends(actor)):
    m = manifest()
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


async def calculate_autopay(body, g):
    m = manifest()
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
    return await calculate_autopay(body, gateway(request))


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
    preview = await calculate_autopay(body, gateway(request))
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
    m = manifest()
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
    m = manifest()
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
    payload = {"initiator": user, "evaluation": evaluation}
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
        if AUTH_MODE == "auth0" and user != os.getenv("JOINT_PARTNER_SUB", ""):
            raise HTTPException(403, "Authenticated user is not the configured partner")
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
    m = manifest()
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
            m = manifest()
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
    m = manifest()
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
