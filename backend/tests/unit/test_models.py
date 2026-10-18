from dataclasses import replace
from datetime import date, datetime

import pytest

from app.domain.demo import demo_results, load_scenario
from app.domain.models import Bill, CashFlow, MoneyContext


@pytest.mark.parametrize("amount", [-1, 1.0, "100", True])
def test_bill_requires_nonnegative_integer_cents(amount):
    with pytest.raises(ValueError):
        Bill("id", "checking", date(2026, 10, 17), amount)


def test_duplicate_ids_rejected():
    ctx = load_scenario("bills")
    with pytest.raises(ValueError):
        replace(ctx, bills=ctx.bills + ctx.bills)


def test_unknown_accounts_rejected():
    ctx = load_scenario("bills")
    with pytest.raises(ValueError):
        replace(ctx, bills=(replace(ctx.bills[0], account_id="unknown"),))


def test_mismatched_linked_payment_rejected():
    ctx = load_scenario("bills")
    with pytest.raises(ValueError):
        replace(ctx, approved_outflows=(CashFlow("bad", "checking_demo_1", date(2026, 10, 21), 1, bill_id="rent"),))


def test_naive_timestamp_rejected():
    with pytest.raises(ValueError):
        replace(load_scenario("bills"), captured_at=datetime(2026, 10, 17))


def test_future_snapshot_rejected():
    ctx = load_scenario("bills")
    with pytest.raises(ValueError):
        replace(ctx, captured_at=ctx.captured_at.replace(year=2027))


def test_unknown_contract_field_rejected():
    with pytest.raises(ValueError):
        MoneyContext.from_dict({"credit_limit": 1000})


def test_all_demo_results_reproducible_with_provenance_and_exact_json():
    first = demo_results()
    assert first == demo_results()
    for result in first.values():
        assert result["sandbox_only"]
        assert result["snapshot_id"]
        assert result["source_flags"]
        assert isinstance(result["metrics"], dict)
    assert first["autopay"]["metrics"]["projected_utilization_pct_after_payment"] == "50.00"
