"""Hypothetical expense affordability from cash snapshots, never forecast totals."""

from .forecasts import cash_events
from .models import DecisionOption, RiskFlag, decision, integer


def evaluate_emergency(context, scenario_cost_cents, reserve_cents=None,
                       account_ids=None, allow_savings=False, horizon=14):
    integer(scenario_cost_cents, "scenario_cost_cents")
    reserve = context.safety_buffer_cents if reserve_cents is None else reserve_cents
    integer(reserve, "reserve_cents")
    candidates = context.checking + (context.savings if allow_savings else ())
    if account_ids is None:
        accounts = candidates
    else:
        if len(set(account_ids)) != len(account_ids):
            raise ValueError("duplicate selected account")
        accounts = tuple(a for a in candidates if a.id in account_ids)
        if len(accounts) != len(account_ids):
            raise ValueError("unknown or disallowed cash account")
    if not accounts:
        raise ValueError("select at least one cash account")
    protected = sum(-e[1] for a in accounts for e in cash_events(context, a.id, horizon) if e[1] < 0)
    total = sum(a.available_cents for a in accounts)
    reserve += sum(a.reserve_cents for a in accounts)
    raw = total - protected - reserve
    available = max(0, raw)
    gap = max(0, scenario_cost_cents - available)
    flags = []
    if raw < 0:
        flags.append(RiskFlag("EXISTING_CASH_SHORTFALL", evidence={"amount_cents": -raw}))
    if gap:
        flags.append(RiskFlag("EMERGENCY_GAP", evidence={"gap_cents": gap}))
    metrics = {"account_ids": [a.id for a in accounts], "liquid_funds_cents": total,
               "protected_obligations_cents": protected, "reserve_cents": reserve,
               "raw_available_cents": raw, "available_for_emergency_cents": available,
               "existing_shortfall_cents": max(0, -raw), "scenario_cost_cents": scenario_cost_cents,
               "potential_gap_cents": gap, "allow_savings": allow_savings}
    options = [DecisionOption("edit_scenario", "Adjust scenario amount", {"affordable_cost_cents": available})]
    if gap and not allow_savings and context.savings:
        options.append(DecisionOption("review_savings", "Review optional savings use", {}, ("RECALCULATE_WITH_SAVINGS",)))
    return decision(context, "emergency", metrics, flags, options)
