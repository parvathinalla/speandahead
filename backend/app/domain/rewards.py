"""Card comparison with explicit ranking preference and exact monetary math."""

from decimal import Decimal, ROUND_HALF_UP

from .models import DecisionOption, RiskFlag, decision, integer, text_id


def utilization(balance_cents, limit_cents):
    if limit_cents <= 0:
        raise ValueError("positive credit limit required")
    return (Decimal(max(0, balance_cents)) * 100 / Decimal(limit_cents)).quantize(Decimal("0.01"))


def recommend_cards(context, purchase_cents, category, merchant_id=None,
                    preference="rewards", max_utilization_bps=None):
    integer(purchase_cents, "purchase_cents", 1)
    text_id(category, "category")
    if preference not in {"rewards", "utilization"}:
        raise ValueError("preference must be rewards or utilization")
    if max_utilization_bps is not None:
        integer(max_utilization_bps, "max_utilization_bps")
        if max_utilization_bps > 10000:
            raise ValueError("max utilization exceeds 100%")
    rows = []
    for card in context.cards:
        reasons = []
        forecast_balance = card.balance_cents + card.projected_charges_cents
        after = forecast_balance + purchase_cents
        if not card.eligible or category in card.excluded_categories:
            reasons.append("CARD_INELIGIBLE")
        if card.limit_cents == 0:
            reasons.append("INVALID_CREDIT_LIMIT")
        if after > card.limit_cents:
            reasons.append("INSUFFICIENT_CREDIT")
        if max_utilization_bps is not None and max(0, after) * 10000 > card.limit_cents * max_utilization_bps:
            reasons.append("UTILIZATION_CONSTRAINT")
        rule = next((r for r in card.rules if r.category == category), None)
        rule = rule or next((r for r in card.rules if r.category == "*"), None)
        reward = None
        cap_used = None
        if rule is not None:
            cap_used = min(purchase_cents, rule.remaining_cap_cents) if rule.remaining_cap_cents is not None else purchase_cents
            reward = int((Decimal(cap_used * rule.rate_bps + (purchase_cents - cap_used) * rule.fallback_rate_bps)
                          / 10000).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
        else:
            reasons.append("REWARD_RULE_UNAVAILABLE")
        rows.append({"card_id": card.id, "eligible": not reasons, "reason_codes": reasons,
                     "expected_reward_cents": reward, "bonus_eligible_purchase_cents": cap_used,
                     "available_credit_cents": max(0, card.limit_cents - forecast_balance),
                     "current_utilization_pct": utilization(forecast_balance, card.limit_cents) if card.limit_cents else None,
                     "projected_utilization_pct": utilization(after, card.limit_cents) if card.limit_cents else None,
                     "source": card.source})
    def rank(row):
        reward = row["expected_reward_cents"] or 0
        pct = row["projected_utilization_pct"] if row["projected_utilization_pct"] is not None else Decimal("Infinity")
        values = (-reward, pct) if preference == "rewards" else (pct, -reward)
        return (not row["eligible"], *values, row["card_id"])
    rows.sort(key=rank)
    eligible = [r for r in rows if r["eligible"]]
    flags = [] if eligible else [RiskFlag("NO_ELIGIBLE_CARD")]
    options = [DecisionOption(r["card_id"], "Compare card " + r["card_id"], r,
                             ("MUTUALLY_EXCLUSIVE_OPTIONS", "PAYDOWN_NOT_ASSUMED_POSTED"), r["eligible"]) for r in rows]
    metrics = {"purchase_cents": purchase_cents, "category": category, "merchant_id": merchant_id,
               "ranking_preference": preference, "cards": rows, "checking_change_cents": 0}
    return decision(context, "cards", metrics, flags, options, eligible[0]["card_id"] if eligible else None)
