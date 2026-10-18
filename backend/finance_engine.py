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


def adaptive_autopay_preview(
    balance, credit_limit, checking, bills_due, buffer, statement_date=None,
    target_tiers=(10, 20, 29),
):
    """Choose the lowest utilization tier reachable without using protected cash."""
    balance_value = money(balance)
    limit = money(credit_limit)
    safe_cash = clamp_positive(money(checking) - money(bills_due) - money(buffer))
    if limit <= 0 or balance_value < 0:
        raise ValueError("Invalid balance or credit limit")

    options = []
    chosen = None
    for target in target_tiers:
        required = clamp_positive(
            balance_value - limit * Decimal(str(target)) / Decimal("100"))
        affordable = required <= safe_cash
        option = {
            "target_pct": float(target),
            "payment_needed": amount(required),
            "affordable": affordable,
        }
        options.append(option)
        if chosen is None and affordable:
            chosen = option

    calculation_target = chosen["target_pct"] if chosen else float(target_tiers[-1])
    result = autopay_preview(
        balance_value, limit, calculation_target, checking, bills_due, buffer,
        statement_date,
    )
    result["adaptive_target"] = True
    result["target_options"] = options
    result["recommended_target_pct"] = (
        chosen["target_pct"] if chosen else None)
    result["target_status"] = "target_selected" if chosen else "monitor_only"

    if chosen is None:
        result["recommended_payment_amount"] = 0.0
        result["projected_utilization_pct"] = result["current_utilization_pct"]
        result["is_full_payment_affordable"] = False
        result["alert_message"] = (
            "No target tier is currently reachable without using money protected "
            "for upcoming bills and the safety buffer. Continue monitoring."
        )
        result["target_explanation"] = (
            "Even the below-30% tier is not cash-safe this cycle, so no early "
            "payment is recommended."
        )
    elif chosen["target_pct"] == float(target_tiers[0]):
        result["target_explanation"] = (
            "The preferred 10% tier is reachable after protecting upcoming bills "
            "and the safety buffer."
        )
    else:
        lower = next(option for option in options if not option["affordable"])
        result["target_explanation"] = (
            f"{chosen['target_pct']:g}% is the lowest cash-safe tier this cycle. "
            f"Reaching {lower['target_pct']:g}% would require "
            f"${money(lower['payment_needed'])}."
        )
    return result


def optimize_card_portfolio(cards, available_budget, target_tiers=(29, 20, 10)):
    """Allocate one cash-safe budget across cards by tier and statement urgency."""
    budget = clamp_positive(available_budget)
    remaining_budget = budget
    normalized = []
    for card in cards:
        limit = money(card["credit_limit"])
        balance = money(card["balance"])
        if limit <= 0 or balance < 0:
            continue
        normalized.append({
            **card,
            "_limit": limit,
            "_balance": balance,
            "_remaining": balance,
            "_payment": Decimal("0.00"),
        })

    # First bring every possible card below the warning ceiling, then improve
    # toward 20% and 10%. Within each tier, the closest statement date wins;
    # utilization breaks ties. This prevents rewards or large limits from
    # crowding out an urgent high-utilization card.
    for target in target_tiers:
        ordered = sorted(
            normalized,
            key=lambda card: (
                str(card.get("statement_date", "9999-12-31")),
                -float(card["_remaining"] / card["_limit"]),
            ),
        )
        for card in ordered:
            needed = clamp_positive(
                card["_remaining"]
                - card["_limit"] * Decimal(str(target)) / Decimal("100"))
            if needed <= 0 or remaining_budget <= 0:
                continue
            payment = min(needed, remaining_budget)
            card["_payment"] += payment
            card["_remaining"] -= payment
            remaining_budget -= payment

    plans = []
    for card in sorted(
        normalized,
        key=lambda item: (
            str(item.get("statement_date", "9999-12-31")),
            -float(item["_balance"] / item["_limit"]),
        ),
    ):
        current_pct = round(float(card["_balance"] / card["_limit"] * 100), 2)
        projected_pct = round(float(card["_remaining"] / card["_limit"] * 100), 2)
        payment = amount(card["_payment"])
        if payment > 0:
            reason = (
                "Prioritized by statement timing and utilization; payment advances "
                "the portfolio toward the next cash-safe tier."
            )
            status = "payment_recommended"
        elif current_pct <= 10:
            reason = "Already within the preferred utilization tier."
            status = "already_preferred"
        else:
            reason = "Protected funds are allocated to more urgent cards first."
            status = "monitor"
        plans.append({
            "account": card.get("account"),
            "display_name": card.get("display_name", card.get("account", "Card")),
            "last4": card.get("last4"),
            "statement_date": card.get("statement_date"),
            "pay_by_date": card.get("pay_by_date"),
            "current_balance": amount(card["_balance"]),
            "credit_limit": amount(card["_limit"]),
            "current_utilization_pct": current_pct,
            "recommended_payment_amount": payment,
            "projected_balance": amount(card["_remaining"]),
            "projected_utilization_pct": projected_pct,
            "status": status,
            "priority_reason": reason,
        })

    total_limit = sum((card["_limit"] for card in normalized), Decimal("0"))
    total_before = sum((card["_balance"] for card in normalized), Decimal("0"))
    total_after = sum((card["_remaining"] for card in normalized), Decimal("0"))
    before_pct = round(float(total_before / total_limit * 100), 2) if total_limit else 0
    after_pct = round(float(total_after / total_limit * 100), 2) if total_limit else 0
    used = budget - remaining_budget
    if not normalized:
        status = "no_cards"
    elif all(plan["projected_utilization_pct"] <= 10 for plan in plans):
        status = "preferred_tier_reached"
    elif all(plan["projected_utilization_pct"] < 30 for plan in plans):
        status = "below_warning_ceiling"
    elif used > 0:
        status = "portfolio_improved"
    else:
        status = "monitor_only"
    return {
        "available_payment_budget": amount(budget),
        "allocated_payment_total": amount(used),
        "unallocated_budget": amount(remaining_budget),
        "aggregate_utilization_before_pct": before_pct,
        "aggregate_utilization_after_pct": after_pct,
        "portfolio_status": status,
        "cards": plans,
        "optimization_order": "29% warning ceiling, then 20%, then 10%; earliest statement first",
        "auto_execution": False,
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
        utilization_after = round(float((balance + price) / limit * 100), 2)
        available_after = max(Decimal("0"), limit - balance - price)
        paydown_to_target = clamp_positive(
            balance + price - limit * Decimal(str(target_pct)) / Decimal("100"))
        choices.append({
            "card_name": name,
            "display_name": rule.get("display_name", name),
            "issuer": rule.get("issuer"),
            "network": rule.get("network"),
            "visual_theme": rule.get("visual_theme", "ocean"),
            "benefit_summary": rule.get("benefit_summary", "Everyday card rewards"),
            "last4": rule.get("last4"),
            "account_id": rule.get("account_id"),
            "reward_rate_pct": float(Decimal(str(rule.get("reward_rates", {}).get(category,
                                                             rule.get("reward_rates", {}).get("other", 0)))) * 100),
            "rewards_amount": amount(cashback),
            "current_utilization_pct": round(float(balance / limit * 100), 2),
            "utilization_after_pct": utilization_after,
            "available_credit_after": amount(available_after),
            "has_capacity": (balance + price <= limit),
            "within_target": ((balance + price) / limit * 100 <= Decimal(str(target_pct))),
            "over_target_by_pct": round(max(0.0, utilization_after - float(target_pct)), 2),
            "paydown_to_target": amount(paydown_to_target),
            "limit": amount(limit),
            "balance": amount(balance),
        })
    # A card that breaches the user's utilization target should not win merely
    # because its reward is larger. Within the target, maximize rewards; above
    # it, minimize utilization first. No credit-score prediction is made.
    valid = [c for c in choices if c["has_capacity"]]
    valid.sort(key=lambda c: (
        not c["within_target"],
        -c["rewards_amount"] if c["within_target"] else c["utilization_after_pct"],
        c["utilization_after_pct"] if c["within_target"] else -c["rewards_amount"],
    ))
    invalid = sorted(
        (c for c in choices if not c["has_capacity"]),
        key=lambda c: c["utilization_after_pct"],
    )
    choices = valid + invalid
    total_limit = sum((money(rule["credit_limit"]) for rule in cards.values()), Decimal("0"))
    total_balance = sum((money(rule["balance"]) for rule in cards.values()), Decimal("0"))
    aggregate_before = round(float(total_balance / total_limit * 100), 2) if total_limit else 0
    aggregate_after = round(float((total_balance + price) / total_limit * 100), 2) if total_limit else 0
    return {
        "purchase_amount": amount(price),
        "purchase_category": category,
        "cards": choices,
        "recommended_card": valid[0] if valid else None,
        "no_safe_card": not any(c["within_target"] for c in valid),
        "no_card_has_capacity": not bool(valid),
        "no_card_within_target": not any(c["within_target"] for c in valid),
        "aggregate_utilization_before_pct": aggregate_before,
        "aggregate_utilization_after_pct": aggregate_after,
        "target_utilization_pct": float(target_pct),
        "recommendation_basis": "Available credit and utilization target before rewards",
        "disclaimer": "Utilization may affect credit scores, but score changes cannot be guaranteed.",
    }


def purchase_guidance(card_result, cashflow):
    """Create an explainable purchase verdict from deterministic inputs."""
    price = money(card_result["purchase_amount"])
    best = card_result.get("recommended_card")
    cash_after_bills = clamp_positive(cashflow.get("projected_end_balance", 0))
    repayment_gap = clamp_positive(price - cash_after_bills)

    if not best:
        verdict = "no_capacity"
        headline = "No card has enough available credit"
        timing = "Reduce the purchase amount or use a different payment method."
    elif cashflow.get("is_shortfall"):
        verdict = "consider_waiting"
        headline = "Protect upcoming bills first"
        timing = (
            f"Resolve the ${money(cashflow.get('shortfall_amount', 0))} "
            "forecast shortfall before adding another repayment obligation."
        )
    elif card_result.get("no_card_within_target"):
        verdict = "caution"
        headline = "Every available card exceeds your utilization target"
        timing = (
            f"A ${money(best.get('paydown_to_target', 0))} paydown on the selected "
            "card would bring this purchase back to the target."
        )
    elif repayment_gap > 0:
        verdict = "caution"
        headline = "The card is suitable, but repayment flexibility is limited"
        timing = (
            f"After scheduled bills, current checking would be ${money(repayment_gap)} "
            "short of fully backing this purchase. Future income is not assumed."
        )
    else:
        verdict = "safe_to_spend"
        headline = "This purchase fits the current plan"
        timing = (
            "Upcoming bills remain covered and current checking after those bills "
            "could back the purchase amount."
        )

    reasons = []
    if best:
        reasons.extend([
            f"Earns an estimated ${money(best['rewards_amount'])} in reward value.",
            f"Card utilization would move from {best['current_utilization_pct']}% "
            f"to {best['utilization_after_pct']}%.",
            f"Leaves ${money(best['available_credit_after'])} of available credit.",
        ])
        reasons.append(
            "Stays within the selected utilization target."
            if best["within_target"] else
            f"Exceeds the selected target by {best['over_target_by_pct']} percentage points."
        )
    reasons.append(
        f"Bills due in the next {cashflow.get('horizon_days', 14)} days total "
        f"${money(cashflow.get('total_bills_due', 0))}."
    )

    for card in card_result["cards"]:
        if not card["has_capacity"]:
            over_limit = clamp_positive(
                money(card["balance"]) + price - money(card["limit"]))
            card["decision_label"] = "Insufficient credit"
            card["decision_explanation"] = (
                f"The purchase would exceed available credit by ${money(over_limit)}."
            )
        elif best and card["card_name"] == best["card_name"]:
            card["decision_label"] = "Recommended"
            card["decision_explanation"] = (
                "Best combination of available credit, utilization and rewards."
            )
        elif not card["within_target"]:
            card["decision_label"] = "Higher utilization"
            card["decision_explanation"] = (
                f"Would exceed the utilization target by {card['over_target_by_pct']} "
                "percentage points."
            )
        else:
            reward_difference = money(best["rewards_amount"]) - money(card["rewards_amount"])
            card["decision_label"] = "Safe alternative"
            card["decision_explanation"] = (
                f"Stays within the target and earns ${money(abs(reward_difference))} "
                f"{'less' if reward_difference >= 0 else 'more'} estimated value."
            )

    alternatives = [
        card for card in card_result["cards"]
        if card["has_capacity"] and (not best or card["card_name"] != best["card_name"])
    ]
    return {
        "verdict": verdict,
        "headline": headline,
        "timing_advice": timing,
        "reasons": reasons,
        "cash_after_upcoming_bills": amount(cash_after_bills),
        "repayment_gap_if_fully_backed": amount(repayment_gap),
        "next_best_card": alternatives[0] if alternatives else None,
        "calculation_note": (
            "This is a planning estimate. A credit-card purchase does not immediately "
            "debit checking, and future income is not assumed."
        ),
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
