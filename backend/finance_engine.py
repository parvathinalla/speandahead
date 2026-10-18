"""Deterministic financial calculations for fictional CreditPilot scenarios.

AI never sets money amounts or authorizes a transfer. All monetary results
are rounded to cents; utilization is a planning estimate, not a credit score.
"""
from datetime import date, timedelta
import calendar
from decimal import Decimal, ROUND_HALF_UP
from typing import Any


def money(value: Any) -> Decimal:
    return Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def amount(value: Any) -> float:
    return float(money(value))


def clamp_positive(value: Any) -> Decimal:
    return max(Decimal("0.00"), money(value))


def next_payment_date(bill, as_of=None):
    """Project next monthly occurrence without changing the underlying bill."""
    today = as_of or date.today()
    start = date.fromisoformat(
        str(bill.get("upcoming_payment_date") or bill["payment_date"])[:10])
    if bill.get("frequency") != "monthly":
        return start
    due_day = int(bill.get("recurring_date") or start.day)
    if start >= today:
        return start
    month = today.month
    year = today.year
    day = min(due_day, calendar.monthrange(year, month)[1])
    proposed = date(year, month, day)
    if proposed < today:
        year, month = (year + 1, 1) if month == 12 else (year, month + 1)
        proposed = date(year, month, min(due_day, calendar.monthrange(year, month)[1]))
    return proposed


def bill_occurrences(bill, today, cutoff):
    if bill.get("status") not in ("pending", "recurring"):
        return
    when = next_payment_date(bill, today)
    recurring = bill.get("frequency") == "monthly"
    original_day = int(bill.get("recurring_date") or when.day)
    while today <= when <= cutoff:
        yield when
        if not recurring:
            break
        year, month = ((when.year + 1, 1) if when.month == 12
                       else (when.year, when.month + 1))
        when = date(year, month, min(original_day, calendar.monthrange(year, month)[1]))


def forecast(checking, savings, bills, horizon_days=14, reserve=0, today=None):
    today = today or date.today()
    cutoff = today + timedelta(days=horizon_days)
    normalized = []
    for row in bills:
        for when in bill_occurrences(row, today, cutoff):
            normalized.append({
                "name": row.get("nickname", row.get("payee", "Bill")),
                "payee": row.get("payee", ""),
                "bill_id": row.get("bill_id"),
                "category": row.get("category", "other"),
                "due_date": when.isoformat(),
                "amount": amount(row["payment_amount"]),
                "source": row.get("source", "nessie"),
            })
    normalized.sort(key=lambda b: (b["due_date"], b["name"]))
    cash = money(checking)
    timeline = [{"date": today.isoformat(), "balance": amount(cash), "event": "Today"}]
    min_cash = cash
    first_shortfall = None
    for bill in normalized:
        cash -= money(bill["amount"])
        min_cash = min(min_cash, cash)
        timeline.append({"date": bill["due_date"], "balance": amount(cash),
                         "event": bill["name"]})
        if first_shortfall is None and cash < money(reserve):
            first_shortfall = {
                "date": bill["due_date"],
                "bill": bill["payee"] or bill["name"],
                "amount": amount(money(reserve) - cash),
            }
    shortage = clamp_positive(money(reserve) - min_cash)
    remaining_savings = clamp_positive(savings)
    transfer = min(shortage, remaining_savings)
    total = sum((money(b["amount"]) for b in normalized), Decimal("0"))
    return {
        "checking_balance": amount(checking),
        "savings_balance": amount(savings),
        "horizon_days": horizon_days,
        "total_bills_due": amount(total),
        "shortfall_amount": amount(shortage),
        "projected_end_balance": amount(cash),
        "is_shortfall": shortage > 0,
        "suggested_savings_transfer": amount(transfer),
        "remaining_shortfall_after_transfer": amount(shortage - transfer),
        "first_shortfall_date": first_shortfall["date"] if first_shortfall else None,
        "first_shortfall_bill": first_shortfall["bill"] if first_shortfall else None,
        "first_shortfall_amount": first_shortfall["amount"] if first_shortfall else 0.0,
        "upcoming_bills": normalized,
        "timeline": timeline,
        "protected_reserve": amount(reserve),
        "projection_assumption": "Future income is not included unless recorded as a received deposit.",
    }


def autopay_preview(balance, credit_limit, target_pct, checking, bills_due, buffer, statement_date=None):
    balance, limit, target = money(balance), money(credit_limit), Decimal(str(target_pct))
    if limit <= 0 or balance < 0 or not (Decimal("0") <= target <= Decimal("100")):
        raise ValueError("Invalid balance, limit, or utilization target")
    required = clamp_positive(balance - limit * target / Decimal("100"))
    safe_cash = clamp_positive(money(checking) - money(bills_due) - money(buffer))
    recommended = min(required, safe_cash)
    return {
        "card_limit": amount(limit),
        "current_balance": amount(balance),
        "current_utilization_pct": round(float(balance / limit * 100), 2),
        "target_utilization_pct": float(target),
        "suggested_paydown_amount": amount(required),
        "checking_funds": amount(checking),
        "upcoming_bills_2weeks": amount(bills_due),
        "safety_buffer": amount(buffer),
        "max_safe_payment_today": amount(safe_cash),
        "is_full_payment_affordable": safe_cash >= required,
        "recommended_payment_amount": amount(recommended),
        "projected_utilization_pct": round(float((balance - recommended) / limit * 100), 2),
        "expected_statement_date": statement_date,
        "payment_status": "proposal_only",
        "auto_execution": False,
        "alert_message": ("Payment exceeds available funds after upcoming bills and buffer."
                          if required > safe_cash else
                          "A payment may reduce the balance reported, but timing is not guaranteed."),
        "disclaimer": "Below 30% is not a credit-score guarantee. Statement date is an estimate.",
    }


def card_comparison(cards, purchase_amount, category, target_pct=30):
    price = money(purchase_amount)
    if price <= 0:
        raise ValueError("Purchase amount must be positive")
    choices = []
    for name, rule in cards.items():
        limit, balance = money(rule["credit_limit"]), money(rule["balance"])
        if limit <= 0:
            continue
        cashback = money(price * Decimal(str(rule.get("reward_rates", {}).get(category,
                                                       rule.get("reward_rates", {}).get("other", 0)))))
        choices.append({
            "card_name": name,
            "display_name": rule.get("display_name", name),
            "issuer": rule.get("issuer"),
            "network": rule.get("network"),
            "last4": rule.get("last4"),
            "account_id": rule.get("account_id"),
            "reward_rate_pct": float(Decimal(str(rule.get("reward_rates", {}).get(category,
                                                             rule.get("reward_rates", {}).get("other", 0)))) * 100),
            "rewards_amount": amount(cashback),
            "current_utilization_pct": round(float(balance / limit * 100), 2),
            "utilization_after_pct": round(float((balance + price) / limit * 100), 2),
            "has_capacity": (balance + price <= limit),
            "within_target": ((balance + price) / limit * 100 <= Decimal(str(target_pct))),
            "limit": amount(limit),
            "balance": amount(balance),
        })
    # Prioritize capacity, target utilization, then cash back. No predicted score.
    valid = [c for c in choices if c["has_capacity"]]
    valid.sort(key=lambda c: (not c["within_target"], -c["rewards_amount"],
                              c["utilization_after_pct"]))
    return {
        "purchase_amount": amount(price),
        "purchase_category": category,
        "cards": choices,
        "recommended_card": valid[0] if valid else None,
        "no_safe_card": not bool(valid),
        "recommendation_basis": "Available credit and chosen utilization target before rewards",
        "disclaimer": "Utilization may affect credit scores, but score changes cannot be guaranteed.",
    }


def emergency(checking, savings, protected_bills, estimated_cost, buffer=0):
    liquid = money(checking) + money(savings)
    protected = money(protected_bills) + money(buffer)
    usable = clamp_positive(liquid - protected)
    cost = clamp_positive(estimated_cost)
    return {
        "total_available_funds": amount(liquid),
        "protected_committed_bills": amount(protected_bills),
        "safety_buffer": amount(buffer),
        "usable_cash_buffer": amount(usable),
        "estimated_emergency_cost": amount(cost),
        "potential_gap": amount(clamp_positive(cost - usable)),
        "is_gap_present": cost > usable,
        "coverage_pct": round(float(100 * usable / cost), 1) if cost else 100.0,
        "explanation": "Scenario estimate based on available cash and protected obligations.",
    }


def joint_risk(amount_value, balance, unusual_threshold=500, fraction=0.35):
    spending = money(amount_value)
    cash = money(balance)
    flagged = spending >= money(unusual_threshold) or (
        cash > 0 and spending / cash >= Decimal(str(fraction)))
    return {
        "is_unusual": flagged,
        "amount": amount(spending),
        "account_balance": amount(cash),
        "risk_reason": ("Exceeds the configured joint-account notification threshold"
                        if flagged else "Below the configured alert threshold"),
        "requires_partner_confirmation": flagged,
        "scope_disclaimer": "Only transactions initiated in this app can wait for approval.",
    }
