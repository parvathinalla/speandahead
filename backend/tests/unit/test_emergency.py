from dataclasses import replace

import pytest

from app.domain.demo import load_scenario
from app.domain.emergency import evaluate_emergency
from app.domain.models import CashFlow


def test_required_emergency_gap():
    result = evaluate_emergency(load_scenario("emergency"), 100000, allow_savings=True)
    assert result.metrics["available_for_emergency_cents"] == 80000
    assert result.metrics["potential_gap_cents"] == 20000


def test_savings_use_is_opt_in():
    result = evaluate_emergency(load_scenario("emergency"), 100000)
    assert result.metrics["available_for_emergency_cents"] == 0
    assert result.metrics["potential_gap_cents"] == 100000


def test_existing_shortage_separate_from_scenario_gap():
    result = evaluate_emergency(load_scenario("bills"), 10000)
    assert result.metrics["raw_available_cents"] == -17000
    assert result.metrics["existing_shortfall_cents"] == 17000
    assert result.metrics["potential_gap_cents"] == 10000


def test_linked_bill_not_deducted_twice():
    ctx = load_scenario("emergency")
    ctx = replace(ctx, approved_outflows=(CashFlow("protected_plan", "checking_demo_1", ctx.bills[0].due_on,
                                                 120000, bill_id="protected"),))
    assert evaluate_emergency(ctx, 100000, allow_savings=True).metrics["potential_gap_cents"] == 20000


def test_all_reserves_protected():
    ctx = load_scenario("emergency")
    ctx = replace(ctx, savings=(replace(ctx.savings[0], reserve_cents=10000),))
    result = evaluate_emergency(ctx, 100000, reserve_cents=5000, allow_savings=True)
    assert result.metrics["potential_gap_cents"] == 35000


@pytest.mark.parametrize("ids", [("checking_demo_1", "checking_demo_1"), ("savings_demo_1",), ("unknown",)])
def test_invalid_or_disallowed_selection(ids):
    with pytest.raises(ValueError):
        evaluate_emergency(load_scenario("emergency"), 100000, account_ids=ids)
