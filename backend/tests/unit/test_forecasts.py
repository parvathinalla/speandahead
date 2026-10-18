from dataclasses import replace
from datetime import date

import pytest

from app.domain.demo import load_scenario
from app.domain.forecasts import forecast_bills, preview_savings_move
from app.domain.models import AccountSnapshot, Bill, CashFlow


def test_required_bill_shortfall():
    result = forecast_bills(load_scenario("bills"))
    assert result.metrics["shortfall_cents"] == 17000
    assert result.metrics["earliest_below_reserve_on"] == date(2026, 10, 21)
    assert len(result.metrics["daily_balances"]) == 14
    assert result.options[0].projected_effects["amount_cents"] == 17000


def test_confirmed_income_before_bill_removes_shortfall():
    ctx = load_scenario("bills")
    ctx = replace(ctx, future_income=(CashFlow("pay", "checking_demo_1", date(2026, 10, 20), 20000),))
    assert forecast_bills(ctx).metrics["shortfall_cents"] == 0


@pytest.mark.parametrize("on,confirmed", [(date(2026, 10, 20), False),
                                         (date(2026, 10, 16), True),
                                         (date(2026, 10, 25), True)])
def test_unreliable_or_late_income_does_not_hide_shortage(on, confirmed):
    ctx = replace(load_scenario("bills"), future_income=(CashFlow("pay", "checking_demo_1", on, 20000, confirmed),))
    assert forecast_bills(ctx).metrics["shortfall_cents"] == 17000


def test_same_day_deposit_has_conservative_settlement_risk():
    ctx = replace(load_scenario("bills"), future_income=(CashFlow("pay", "checking_demo_1", date(2026, 10, 21), 20000),))
    result = forecast_bills(ctx)
    assert result.metrics["projected_end_balance_cents"] == 3000
    assert result.metrics["shortfall_cents"] == 17000


@pytest.mark.parametrize("status,reflected", [("paid", False), ("canceled", False), ("pending", True)])
def test_settled_or_reflected_bill_not_deducted_again(status, reflected):
    ctx = load_scenario("bills")
    ctx = replace(ctx, bills=(replace(ctx.bills[0], status=status, reflected_in_available=reflected),))
    assert forecast_bills(ctx).metrics["projected_end_balance_cents"] == 45000


def test_linked_scheduled_bill_counted_once():
    ctx = replace(load_scenario("bills"), approved_outflows=(
        CashFlow("rent_schedule", "checking_demo_1", date(2026, 10, 21), 62000, bill_id="rent"),))
    assert forecast_bills(ctx).metrics["projected_end_balance_cents"] == -17000


def test_pending_reflected_linked_payment_not_counted_twice():
    ctx = replace(load_scenario("bills"), approved_outflows=(
        CashFlow("rent_schedule", "checking_demo_1", date(2026, 10, 21), 62000,
                 reflected_in_available=True, bill_id="rent"),))
    assert forecast_bills(ctx).metrics["projected_end_balance_cents"] == 45000


def test_due_date_not_postponed_by_scheduling():
    ctx = replace(load_scenario("bills"), approved_outflows=(
        CashFlow("rent_schedule", "checking_demo_1", date(2026, 12, 21), 62000, bill_id="rent"),))
    assert forecast_bills(ctx).metrics["shortfall_cents"] == 17000


def test_deterministic_same_day_bills():
    ctx = load_scenario("bills")
    bills = (replace(ctx.bills[0], amount_cents=20000),
             Bill("bill2", "checking_demo_1", date(2026, 10, 21), 42000))
    assert (forecast_bills(replace(ctx, bills=bills)).metrics ==
            forecast_bills(replace(ctx, bills=bills[::-1])).metrics)


def test_savings_reserve_and_scheduled_obligations_protected():
    ctx = load_scenario("bills")
    ctx = replace(ctx, approved_outflows=(CashFlow("save_debit", "savings_demo_1", date(2026, 10, 20), 60000),))
    result = preview_savings_move(ctx, "savings_demo_1", "checking_demo_1", 17000)
    assert result.metrics["safe_transfer_cap_cents"] == 10000
    assert not result.options[0].enabled


def test_negative_checking_keeps_shortage():
    ctx = replace(load_scenario("bills"), checking=(AccountSnapshot("checking_demo_1", -500),))
    assert forecast_bills(ctx).metrics["shortfall_cents"] == 62500


def test_partial_data_disables_suggestions():
    result = forecast_bills(replace(load_scenario("bills"), complete=False))
    assert result.status == "unavailable"
    assert all(not option.enabled for option in result.options)


def test_multiple_checking_requires_selection():
    ctx = load_scenario("bills")
    ctx = replace(ctx, checking=ctx.checking + (AccountSnapshot("second", 999999),))
    with pytest.raises(ValueError):
        forecast_bills(ctx)
    assert forecast_bills(ctx, account_id="checking_demo_1").metrics["shortfall_cents"] == 17000


@pytest.mark.parametrize("amount", [0, -1, 0.5, True])
def test_invalid_transfer_amount(amount):
    with pytest.raises(ValueError):
        preview_savings_move(load_scenario("bills"), "savings_demo_1", "checking_demo_1", amount)
