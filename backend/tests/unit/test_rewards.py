from dataclasses import replace
from decimal import Decimal

import pytest

from app.domain.demo import load_scenario
from app.domain.models import RewardRule
from app.domain.rewards import recommend_cards


def test_reward_dollars_and_credit_ledger():
    ctx = load_scenario("cards")
    result = recommend_cards(ctx, 12000, "groceries")
    first, second = result.metrics["cards"]
    assert first["expected_reward_cents"] == 360
    assert second["expected_reward_cents"] == 240
    assert first["projected_utilization_pct"] == Decimal("87.00")
    assert second["projected_utilization_pct"] == Decimal("31.00")
    assert ctx.checking[0].available_cents == 45000
    assert result.metrics["checking_change_cents"] == 0


def test_preference_changes_recommendation():
    ctx = load_scenario("cards")
    assert recommend_cards(ctx, 12000, "groceries").recommendation_option_id == "card_demo_1"
    assert recommend_cards(ctx, 12000, "groceries", preference="utilization").recommendation_option_id == "card_demo_2"


def test_pending_charges_reduce_headroom():
    ctx = load_scenario("cards")
    ctx = replace(ctx, cards=(replace(ctx.cards[0], projected_charges_cents=20000),))
    result = recommend_cards(ctx, 12000, "groceries")
    assert "INSUFFICIENT_CREDIT" in result.metrics["cards"][0]["reason_codes"]
    assert result.recommendation_option_id is None


@pytest.mark.parametrize("remaining,expected", [(0, 120), (5000, 220), (12000, 360)])
def test_reward_caps_and_base_rate(remaining, expected):
    ctx = load_scenario("cards")
    card = replace(ctx.cards[0], rules=(RewardRule("groceries", 300, remaining, 100),))
    result = recommend_cards(replace(ctx, cards=(card,)), 12000, "groceries")
    assert result.metrics["cards"][0]["expected_reward_cents"] == expected


def test_rewards_round_half_up_at_cent():
    ctx = load_scenario("cards")
    result = recommend_cards(ctx, 50, "groceries")
    assert result.metrics["cards"][0]["expected_reward_cents"] == 2


def test_refund_credit_is_not_negative_utilization():
    ctx = load_scenario("cards")
    ctx = replace(ctx, cards=(replace(ctx.cards[0], balance_cents=-20000),))
    assert recommend_cards(ctx, 12000, "groceries").metrics["cards"][0]["projected_utilization_pct"] == 0


def test_zero_limit_returns_disabled_option():
    ctx = load_scenario("cards")
    ctx = replace(ctx, cards=(replace(ctx.cards[0], limit_cents=0),))
    result = recommend_cards(ctx, 12000, "groceries")
    assert not result.options[0].enabled
    assert result.metrics["cards"][0]["projected_utilization_pct"] is None


def test_category_exclusion_and_user_utilization_constraint():
    ctx = load_scenario("cards")
    ctx = replace(ctx, cards=(replace(ctx.cards[0], excluded_categories=("groceries",)), ctx.cards[1]))
    result = recommend_cards(ctx, 12000, "groceries", max_utilization_bps=3000)
    assert result.recommendation_option_id is None
    assert all(not option.enabled for option in result.options)


def test_missing_rewards_not_invented():
    ctx = load_scenario("cards")
    result = recommend_cards(replace(ctx, cards=(replace(ctx.cards[0], rules=()),)), 12000, "groceries")
    assert result.metrics["cards"][0]["expected_reward_cents"] is None
    assert result.recommendation_option_id is None
