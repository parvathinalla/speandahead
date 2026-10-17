from dataclasses import replace
from datetime import timedelta

import pytest

from app.domain.autopay import AutoPayPlan, preview_autopay, recheck_autopay_plan
from app.domain.demo import load_scenario
from app.domain.models import CashFlow


def preview(ctx, **kwargs):
    return preview_autopay(ctx, "card_demo_1", 2900, 46000, **kwargs)


def live_context_and_plan():
    ctx = load_scenario("autopay")
    ctx = replace(ctx, checking=(replace(ctx.checking[0], source="nessie"),),
                  source_flags=("nessie_accounts", "fixture_card_profile"))
    plan = AutoPayPlan("plan_1", "card_demo_1", "checking_demo_1", 25000, 2900, 25000,
                      ctx.evaluated_at, ctx.evaluated_at + timedelta(hours=1), ctx.cards[0].close_estimate)
    return ctx, plan


def test_required_autopay_scenario():
    result = preview(load_scenario("autopay"))
    assert result.metrics["target_payment_cents"] == 46000
    assert result.metrics["safe_payment_cents"] == 25000
    assert result.metrics["proposed_payment_cents"] == 25000
    assert result.metrics["projected_utilization_pct_after_payment"] == 50
    assert not result.metrics["target_reachable"]
    assert "TARGET_NOT_AFFORDABLE" in [r.code for r in result.risk_flags]


def test_cannot_spend_bill_or_scheduled_payment_money_twice():
    ctx = load_scenario("autopay")
    ctx = replace(ctx, approved_outflows=(CashFlow("other_plan", "checking_demo_1", ctx.evaluated_at.date(), 20000),))
    assert preview(ctx).metrics["proposed_payment_cents"] == 5000


def test_reserve_is_protected_before_future_income():
    ctx = load_scenario("autopay")
    ctx = replace(ctx, checking=(replace(ctx.checking[0], available_cents=10000),),
                  future_income=(CashFlow("pay", "checking_demo_1", ctx.evaluated_at.date() + timedelta(days=1), 50000),))
    assert preview(ctx).metrics["proposed_payment_cents"] == 0


def test_target_rounding_never_exceeds_fractional_cent_target():
    ctx = load_scenario("autopay")
    ctx = replace(ctx, cards=(replace(ctx.cards[0], limit_cents=101, balance_cents=100),))
    result = preview(ctx)
    assert result.metrics["target_balance_cents"] == 29
    assert result.metrics["proposed_payment_cents"] == 71


def test_user_cap_limits_proposal():
    result = preview_autopay(load_scenario("autopay"), "card_demo_1", 2900, 10000)
    assert result.metrics["proposed_payment_cents"] == 10000


def test_pending_charges_never_allow_overpaying_posted_debt():
    ctx = load_scenario("autopay")
    ctx = replace(ctx, cards=(replace(ctx.cards[0], balance_cents=100, projected_charges_cents=50000),))
    assert preview(ctx).metrics["proposed_payment_cents"] == 100


@pytest.mark.parametrize("change", [{"limit_cents": 0}, {"close_estimate": None}, {"eligible": False}])
def test_invalid_card_disables_preview(change):
    ctx = load_scenario("autopay")
    result = preview(replace(ctx, cards=(replace(ctx.cards[0], **change),)))
    assert result.status == "unavailable"
    assert result.metrics["proposed_payment_cents"] == 0
    assert not result.metrics["target_reachable"]


def test_live_recheck_is_eligibility_not_execution():
    ctx, plan = live_context_and_plan()
    result = recheck_autopay_plan(ctx, plan)
    assert result.metrics["can_execute"]
    assert result.metrics["suggested_state"] == "READY_FOR_ACTION_GATE"


def test_falling_funds_require_review():
    ctx, plan = live_context_and_plan()
    ctx = replace(ctx, checking=(replace(ctx.checking[0], available_cents=40000),))
    assert not recheck_autopay_plan(ctx, plan).metrics["can_execute"]


@pytest.mark.parametrize("state", ["CANCELED", "EXECUTED_SANDBOX", "DRAFT", "PENDING_APPROVAL"])
def test_only_scheduled_plan_can_pass(state):
    ctx, plan = live_context_and_plan()
    assert not recheck_autopay_plan(ctx, replace(plan, state=state)).metrics["can_execute"]


@pytest.mark.parametrize("change", ["stale", "expired", "revoked", "fixture", "partial", "changed_close", "not_due", "offline"])
def test_execution_safety_gates(change):
    ctx, plan = live_context_and_plan()
    if change == "stale":
        ctx = replace(ctx, evaluated_at=ctx.evaluated_at + timedelta(minutes=6))
    elif change == "expired":
        plan = replace(plan, consent_expires_at=ctx.evaluated_at)
    elif change == "revoked":
        plan = replace(plan, consent_valid=False)
    elif change == "fixture":
        ctx = replace(ctx, checking=(replace(ctx.checking[0], source="fixture"),))
    elif change == "partial":
        ctx = replace(ctx, complete=False)
    elif change == "changed_close":
        ctx = replace(ctx, cards=(replace(ctx.cards[0], close_estimate=ctx.cards[0].close_estimate + timedelta(days=1)),))
    elif change == "not_due":
        plan = replace(plan, run_at=ctx.evaluated_at + timedelta(minutes=1))
    else:
        ctx = replace(ctx, source_flags=("nessie_unavailable",))
    assert not recheck_autopay_plan(ctx, plan).metrics["can_execute"]


def test_recheck_replaces_own_reservation_only():
    ctx, plan = live_context_and_plan()
    flow = CashFlow("this_plan", "checking_demo_1", plan.run_at.date(), plan.amount_cents)
    ctx = replace(ctx, approved_outflows=(flow,))
    plan = replace(plan, reserved_outflow_id=flow.id)
    assert recheck_autopay_plan(ctx, plan).metrics["can_execute"]
    ctx = replace(ctx, approved_outflows=(flow, replace(flow, id="second_plan", amount_cents=100)))
    assert not recheck_autopay_plan(ctx, plan).metrics["can_execute"]


def test_reservation_mismatch_cannot_be_excluded():
    ctx, plan = live_context_and_plan()
    plan = replace(plan, reserved_outflow_id="nonexistent")
    assert not recheck_autopay_plan(ctx, plan).metrics["can_execute"]
