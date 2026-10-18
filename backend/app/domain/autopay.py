"""Pure paydown preview and scheduler affordability recheck; never moves money."""

from dataclasses import dataclass
from datetime import date, datetime

from .forecasts import ledger, select_account
from .models import DecisionOption, RiskFlag, calendar_date, decision, integer, text_id, utc
from .rewards import utilization


@dataclass(frozen=True)
class AutoPayPlan:
    id: str
    card_id: str
    source_account_id: str
    amount_cents: int
    target_bps: int
    max_payment_cents: int
    run_at: datetime
    consent_expires_at: datetime
    close_estimate: date
    state: str = "SCHEDULED"
    consent_valid: bool = True
    reserved_outflow_id: str | None = None

    def __post_init__(self):
        for value in (self.id, self.card_id, self.source_account_id):
            text_id(value)
        integer(self.amount_cents, "amount_cents", 1)
        integer(self.max_payment_cents, "max_payment_cents", 1)
        integer(self.target_bps, "target_bps")
        if self.target_bps > 10000 or self.amount_cents > self.max_payment_cents:
            raise ValueError("plan exceeds target range or consent cap")
        object.__setattr__(self, "run_at", utc(self.run_at))
        object.__setattr__(self, "consent_expires_at", utc(self.consent_expires_at))
        calendar_date(self.close_estimate)
        if type(self.consent_valid) is not bool:
            raise ValueError("consent_valid must be boolean")


def preview_autopay(context, card_id, target_bps, max_payment_cents,
                    source_account_id=None, horizon=14, exclude_outflow_id=None):
    integer(target_bps, "target_bps")
    integer(max_payment_cents, "max_payment_cents")
    if target_bps > 10000:
        raise ValueError("target exceeds 100%")
    account = select_account(context.checking, source_account_id)
    card = next((c for c in context.cards if c.id == card_id), None)
    if card is None:
        raise ValueError("unknown card")
    integer(horizon, "horizon", 1)
    if card.close_estimate is not None:
        horizon = max(horizon, (card.close_estimate - context.evaluated_at.date()).days + 1)
    reserve = context.safety_buffer_cents + account.reserve_cents
    projection = ledger(context, account, horizon, reserve, exclude_outflow_id)
    forecast_balance = card.balance_cents + card.projected_charges_cents
    # Floor the allowed target balance so the resulting utilization is <= target.
    target_balance = card.limit_cents * target_bps // 10000
    theoretical = max(0, forecast_balance - target_balance)
    cap = projection["safe_outflow_cents"]
    flags = []
    if not card.eligible:
        flags.append(RiskFlag("CARD_INELIGIBLE", "error"))
    if card.limit_cents <= 0:
        flags.append(RiskFlag("INVALID_CREDIT_LIMIT", "error"))
    if card.close_estimate is None:
        flags.append(RiskFlag("MISSING_CLOSE_ESTIMATE", "error"))
    elif card.close_estimate < context.evaluated_at.date():
        flags.append(RiskFlag("CLOSE_ESTIMATE_PASSED", "error"))
    # A modeled pending purchase can raise the target need, but cannot be paid
    # before it posts. Avoid generating a credit by overpaying posted debt.
    proposed = min(theoretical, cap, max_payment_cents, max(0, card.balance_cents))
    if not context.complete or any(f.severity == "error" for f in flags):
        proposed = 0
    if theoretical > cap:
        flags.append(RiskFlag("TARGET_NOT_AFFORDABLE", evidence={"safe_payment_cents": cap}))
    if theoretical > max_payment_cents:
        flags.append(RiskFlag("USER_CAP_LIMITS_PAYMENT"))
    if theoretical > max(0, card.balance_cents):
        flags.append(RiskFlag("PENDING_CHARGES_NOT_PAYABLE"))
    metrics = {"card_id": card_id, "source_account_id": account.id, "target_bps": target_bps,
               "target_payment_cents": theoretical, "target_balance_cents": target_balance,
               "checking_available_cents": account.available_cents,
               "protected_obligations_cents": projection["protected_obligations_cents"],
               "reserve_cents": reserve, "safe_payment_cents": cap,
               "max_payment_cents": max_payment_cents, "proposed_payment_cents": proposed,
               "target_reachable": card.limit_cents > 0 and proposed >= theoretical and context.complete
                                   and not any(f.severity == "error" for f in flags),
               "current_utilization_pct": utilization(card.balance_cents, card.limit_cents) if card.limit_cents else None,
               "projected_utilization_pct_after_payment": utilization(forecast_balance - proposed, card.limit_cents) if card.limit_cents else None,
               "close_estimate": card.close_estimate, "horizon_days": horizon}
    option = DecisionOption("safe_paydown", "Review affordable paydown", metrics,
                            ("EXPLICIT_APPROVAL", "FRESH_SNAPSHOT", "ESTIMATED_CLOSE_DATE", "RECHECK_BEFORE_EXECUTION"), proposed > 0)
    return decision(context, "autopay", metrics, flags, [option], "safe_paydown" if proposed else None, True)


def recheck_autopay_plan(context_fresh, plan, max_snapshot_age_seconds=300):
    """Return eligibility to the guarded scheduler, not execution success.

    Auth, consent signature/ownership, idempotency and locking remain API duties.
    The trusted scheduler must provide evaluated_at from its current UTC clock.
    """
    integer(max_snapshot_age_seconds, "max_snapshot_age_seconds", 1)
    ctx = context_fresh
    now = ctx.evaluated_at
    flags = []
    if plan.state != "SCHEDULED":
        flags.append(RiskFlag("PLAN_NOT_SCHEDULED", "error"))
    if not plan.consent_valid or now >= plan.consent_expires_at:
        flags.append(RiskFlag("CONSENT_EXPIRED_OR_REVOKED", "error"))
    if now < plan.run_at:
        flags.append(RiskFlag("PLAN_NOT_DUE", "error"))
    if (now - ctx.captured_at).total_seconds() > max_snapshot_age_seconds:
        flags.append(RiskFlag("STALE_SNAPSHOT", "error"))
    account = next((a for a in ctx.checking if a.id == plan.source_account_id), None)
    card = next((c for c in ctx.cards if c.id == plan.card_id), None)
    if account is None or card is None:
        flags.append(RiskFlag("PLAN_RESOURCE_UNAVAILABLE", "error"))
    if account is not None and account.source != "nessie":
        flags.append(RiskFlag("LIVE_CASH_REQUIRED", "error"))
    if any("unavailable" in f.lower() or "fallback" in f.lower() for f in ctx.source_flags):
        flags.append(RiskFlag("PROVIDER_UNAVAILABLE", "error"))
    if card is not None and card.close_estimate != plan.close_estimate:
        flags.append(RiskFlag("CLOSE_ESTIMATE_CHANGED", "error"))
    excluded = None
    if plan.reserved_outflow_id is not None:
        reservation = next((f for f in ctx.approved_outflows if f.id == plan.reserved_outflow_id), None)
        if (reservation is None or reservation.account_id != plan.source_account_id or
                reservation.amount_cents != plan.amount_cents or reservation.bill_id is not None or
                reservation.on != plan.run_at.date() or reservation.reflected_in_available):
            flags.append(RiskFlag("PLAN_RESERVATION_MISMATCH", "error"))
        else:
            excluded = reservation.id  # replace this plan's reservation, keep every other one
    preview = None
    if account is not None and card is not None:
        preview = preview_autopay(ctx, plan.card_id, plan.target_bps, plan.max_payment_cents,
                                  plan.source_account_id, exclude_outflow_id=excluded)
        flags.extend(f for f in preview.risk_flags if f.severity == "error")
        if plan.amount_cents > preview.metrics["proposed_payment_cents"]:
            flags.append(RiskFlag("PLAN_AMOUNT_NO_LONGER_SAFE", "error"))
    allowed = not flags and ctx.complete
    metrics = {"plan_id": plan.id, "can_execute": allowed, "approved_amount_cents": plan.amount_cents,
               "permitted_payment_cents": plan.amount_cents if allowed else 0,
               "suggested_state": "READY_FOR_ACTION_GATE" if allowed else "NEEDS_REVIEW",
               "preview": preview.to_dict() if preview else None}
    return decision(ctx, "autopay_recheck", metrics, flags, requires_approval=not allowed)
