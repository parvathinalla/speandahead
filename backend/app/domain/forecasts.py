"""Dated cash commitments shared by forecasts, savings, emergency and AutoPay."""

from datetime import timedelta

from .models import DecisionOption, RiskFlag, decision, integer


def select_account(accounts, account_id=None):
    matches = [a for a in accounts if account_id is None or a.id == account_id]
    if len(matches) != 1:
        raise ValueError("select exactly one eligible account")
    return matches[0]


def cash_events(context, account_id, horizon=14, exclude_outflow_id=None):
    integer(horizon, "horizon", 1)
    if horizon > 366:
        raise ValueError("horizon exceeds 366 days")
    start = context.evaluated_at.date()
    end = start + timedelta(days=horizon - 1)
    events = []
    linked = {f.bill_id: f for f in context.approved_outflows if f.bill_id is not None}
    for bill in context.bills:
        if bill.account_id != account_id or bill.status in {"paid", "canceled"} or bill.reflected_in_available:
            continue
        flow = linked.get(bill.id)
        if flow and flow.reflected_in_available:
            continue
        # Scheduling a bill does not erase it or postpone its contractual due date.
        when = min(bill.due_on, flow.on) if flow else bill.due_on
        when = max(start, when)  # overdue unpaid bills are protected immediately
        if when <= end:
            events.append((when, -bill.amount_cents, "bill:" + bill.id))
    for flow in context.approved_outflows:
        if (flow.account_id == account_id and flow.bill_id is None
                and flow.id != exclude_outflow_id and not flow.reflected_in_available):
            when = max(start, flow.on)
            if when <= end:
                events.append((when, -flow.amount_cents, "outflow:" + flow.id))
    for flow in context.future_income:
        # A past unposted deposit is delayed, even if originally confirmed.
        if (flow.account_id == account_id and flow.confirmed and not flow.reflected_in_available
                and start <= flow.on <= end):
            events.append((flow.on, flow.amount_cents, "income:" + flow.id))
    return sorted(events, key=lambda e: (e[0], e[1] >= 0, e[2]))


def ledger(context, account, horizon=14, reserve_cents=0, exclude_outflow_id=None):
    events = cash_events(context, account.id, horizon, exclude_outflow_id)
    balance = account.available_cents
    minimum = balance
    conservative_minimum = balance
    earliest = context.evaluated_at.date() if balance < reserve_cents else None
    series = []
    for offset in range(horizon):
        day = context.evaluated_at.date() + timedelta(days=offset)
        today = [e for e in events if e[0] == day]
        outflow = -sum(e[1] for e in today if e[1] < 0)
        inflow = sum(e[1] for e in today if e[1] > 0)
        # Unknown same-day settlement order: do not spend an unposted deposit first.
        intraday_low = balance - outflow
        conservative_minimum = min(conservative_minimum, intraday_low)
        balance += inflow - outflow
        minimum = min(minimum, balance)
        if earliest is None and intraday_low < reserve_cents:
            earliest = day
        series.append({"date": day, "inflow_cents": inflow, "outflow_cents": outflow,
                       "end_balance_cents": balance, "conservative_low_cents": intraday_low,
                       "commitment_ids": [e[2] for e in today if e[1] < 0]})
    return {"daily_balances": series, "projected_end_balance_cents": balance,
            "lowest_day_end_balance_cents": minimum,
            "lowest_conservative_balance_cents": conservative_minimum,
            "earliest_below_reserve_on": earliest,
            "shortfall_cents": max(0, reserve_cents - conservative_minimum),
            "safe_outflow_cents": max(0, conservative_minimum - reserve_cents),
            "protected_obligations_cents": -sum(e[1] for e in events if e[1] < 0)}


def forecast_bills(context, horizon=14, account_id=None):
    account = select_account(context.checking, account_id)
    reserve = context.safety_buffer_cents + account.reserve_cents
    metrics = ledger(context, account, horizon, reserve)
    metrics.update(account_id=account.id, checking_available_cents=account.available_cents,
                   reserve_cents=reserve, horizon_days=horizon)
    flags = []
    options = []
    if metrics["shortfall_cents"]:
        flags.append(RiskFlag("BILL_SHORTFALL", evidence={"shortfall_cents": metrics["shortfall_cents"],
                                                       "date": metrics["earliest_below_reserve_on"]}))
        for savings in sorted(context.savings, key=lambda a: a.id):
            cap = ledger(context, savings, horizon, savings.reserve_cents)["safe_outflow_cents"]
            amount = min(cap, metrics["shortfall_cents"])
            options.append(DecisionOption("savings:" + savings.id, "Review savings transfer",
                           {"source_id": savings.id, "target_id": account.id, "amount_cents": amount,
                            "remaining_shortfall_cents": metrics["shortfall_cents"] - amount},
                           ("EXPLICIT_APPROVAL", "FRESH_SNAPSHOT", "MUTUALLY_EXCLUSIVE_OPTIONS"), amount > 0))
    if any(not f.confirmed or f.on < context.evaluated_at.date()
           for f in context.future_income if f.account_id == account.id and not f.reflected_in_available):
        flags.append(RiskFlag("UNRELIABLE_INCOME_EXCLUDED", "info"))
    return decision(context, "bills", metrics, flags, options, requires_approval=bool(options))


def preview_savings_move(context, source_id, target_id, amount_cents, horizon=14):
    integer(amount_cents, "amount_cents", 1)
    savings = select_account(context.savings, source_id)
    checking = select_account(context.checking, target_id)
    cap = ledger(context, savings, horizon, savings.reserve_cents)["safe_outflow_cents"]
    flags = [] if amount_cents <= cap else [RiskFlag("INSUFFICIENT_UNPROTECTED_SAVINGS")]
    metrics = {"source_id": source_id, "target_id": target_id, "requested_cents": amount_cents,
               "safe_transfer_cap_cents": cap, "feasible": amount_cents <= cap,
               "projected_savings_cents": savings.available_cents - amount_cents,
               "projected_checking_cents": checking.available_cents + amount_cents}
    option = DecisionOption("savings_transfer", "Review savings transfer", metrics,
                            ("EXPLICIT_APPROVAL", "FRESH_SNAPSHOT"), amount_cents <= cap)
    return decision(context, "savings", metrics, flags, [option],
                    "savings_transfer" if option.enabled else None, True)
