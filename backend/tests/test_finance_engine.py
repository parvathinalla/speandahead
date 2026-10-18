from finance_engine import (adaptive_autopay_preview, forecast, card_comparison, autopay_preview,
                            emergency, joint_risk, optimize_card_portfolio,
                            purchase_guidance)
from datetime import date, timedelta

def test_bill_shortfall():
    today = date.today()
    bills = [{"nickname": "Rent", "payment_date": (today+timedelta(days=3)).isoformat(),
              "status":"pending", "payment_amount":400},
             {"nickname": "Power", "payment_date": (today+timedelta(days=7)).isoformat(),
              "status":"pending", "payment_amount":150},
             {"nickname": "Internet", "payment_date": (today+timedelta(days=12)).isoformat(),
              "status":"pending", "payment_amount":100}]
    r = forecast(500, 1200, bills)
    assert r["total_bills_due"] == 650
    assert r["shortfall_amount"] == 150
    assert r["suggested_savings_transfer"] == 150
    assert r["first_shortfall_bill"] == "Power"
    assert r["first_shortfall_date"] == (today+timedelta(days=7)).isoformat()
    assert r["first_shortfall_amount"] == 50

def test_autopay_protected_funds():
    r = autopay_preview(750, 1000, 29, 600, 250, 100)
    assert r["suggested_paydown_amount"] == 460
    assert r["recommended_payment_amount"] == 250
    assert r["auto_execution"] is False


def test_adaptive_autopay_chooses_lowest_cash_safe_tier():
    result = adaptive_autopay_preview(
        balance=500, credit_limit=1000, checking=550, bills_due=200, buffer=100)
    assert result["recommended_target_pct"] == 29
    assert result["recommended_payment_amount"] == 210
    assert [option["affordable"] for option in result["target_options"]] == [
        False, False, True]


def test_adaptive_autopay_monitors_when_no_tier_is_cash_safe():
    result = adaptive_autopay_preview(
        balance=500, credit_limit=1000, checking=250, bills_due=200, buffer=100)
    assert result["recommended_target_pct"] is None
    assert result["recommended_payment_amount"] == 0
    assert result["projected_utilization_pct"] == 50
    assert result["target_status"] == "monitor_only"


def test_portfolio_optimizer_prioritizes_warning_ceiling_and_urgency():
    cards = [
        {"account": "later", "display_name": "Later", "last4": "1111",
         "balance": 600, "credit_limit": 1000,
         "statement_date": "2026-11-20", "pay_by_date": "2026-11-17"},
        {"account": "sooner", "display_name": "Sooner", "last4": "2222",
         "balance": 500, "credit_limit": 1000,
         "statement_date": "2026-11-10", "pay_by_date": "2026-11-07"},
    ]
    result = optimize_card_portfolio(cards, 300)
    indexed = {card["account"]: card for card in result["cards"]}
    assert indexed["sooner"]["recommended_payment_amount"] == 210
    assert indexed["sooner"]["projected_utilization_pct"] == 29
    assert indexed["later"]["recommended_payment_amount"] == 90
    assert result["allocated_payment_total"] == 300
    assert result["aggregate_utilization_after_pct"] == 40


def test_portfolio_optimizer_never_exceeds_protected_budget():
    cards = [{"account": "a", "balance": 900, "credit_limit": 1000,
              "statement_date": "2026-11-10"}]
    result = optimize_card_portfolio(cards, 125)
    assert result["allocated_payment_total"] == 125
    assert result["cards"][0]["projected_balance"] == 775
    assert result["auto_execution"] is False

def test_rewards():
    options = {"A":{"balance":750,"credit_limit":1000,"reward_rates":{"groceries":0.03}},
               "B":{"balance":200,"credit_limit":2000,"reward_rates":{"groceries":0.02}}}
    r = card_comparison(options, 120, "groceries")
    assert r["recommended_card"]["card_name"] == "B"


def test_over_target_cards_choose_lower_utilization_before_rewards():
    options = {
        "nearly_safe": {
            "balance": 300, "credit_limit": 1000,
            "reward_rates": {"groceries": 0.01},
        },
        "high_utilization": {
            "balance": 900, "credit_limit": 2000,
            "reward_rates": {"groceries": 0.05},
        },
    }
    result = card_comparison(options, 20, "groceries", target_pct=30)
    assert result["recommended_card"]["card_name"] == "nearly_safe"
    assert result["no_card_within_target"] is True
    assert result["no_card_has_capacity"] is False


def test_card_comparison_reports_capacity_and_aggregate_utilization():
    options = {
        "A": {"balance": 200, "credit_limit": 1000, "reward_rates": {"other": .01}},
        "B": {"balance": 300, "credit_limit": 1000, "reward_rates": {"other": .02}},
    }
    result = card_comparison(options, 100, "other")
    assert result["aggregate_utilization_before_pct"] == 25
    assert result["aggregate_utilization_after_pct"] == 30
    assert result["recommended_card"]["available_credit_after"] == 700


def test_purchase_guidance_is_explainable_and_bill_aware():
    cards = card_comparison({
        "A": {"balance": 100, "credit_limit": 1000,
              "reward_rates": {"dining": .03}},
        "B": {"balance": 50, "credit_limit": 2000,
              "reward_rates": {"dining": .01}},
    }, 50, "dining")
    cashflow = {
        "projected_end_balance": 500, "is_shortfall": False,
        "shortfall_amount": 0, "total_bills_due": 300, "horizon_days": 14,
    }
    guidance = purchase_guidance(cards, cashflow)
    assert guidance["verdict"] == "safe_to_spend"
    assert guidance["reasons"]
    assert cards["recommended_card"]["decision_label"] == "Recommended"
    assert guidance["next_best_card"]["decision_label"] == "Safe alternative"


def test_purchase_guidance_prioritizes_existing_bill_shortfall():
    cards = card_comparison({
        "A": {"balance": 100, "credit_limit": 1000,
              "reward_rates": {"other": .01}},
    }, 50, "other")
    guidance = purchase_guidance(cards, {
        "projected_end_balance": -40, "is_shortfall": True,
        "shortfall_amount": 40, "total_bills_due": 600, "horizon_days": 14,
    })
    assert guidance["verdict"] == "consider_waiting"

def test_emergency_shortfall():
    assert emergency(500,1200,650,1000,300)["potential_gap"] == 250

def test_joint_flags():
    assert joint_risk(850,2000)["requires_partner_confirmation"]
    assert not joint_risk(20,2000)["requires_partner_confirmation"]


def test_recurring_bills_roll_forward_in_future_months():
    from finance_engine import next_payment_date
    start = date(2026, 10, 17)
    bill = {
        "payee": "Internet", "nickname": "Internet", "status": "pending",
        "payment_date": "2026-09-30", "upcoming_payment_date": "2026-09-30",
        "recurring_date": 30, "frequency": "monthly", "payment_amount": 70,
        "source": "synthetic_banking_demo",
    }
    assert next_payment_date(bill, start) == date(2026, 10, 30)
    x = forecast(1000, 200, [bill], horizon_days=110, today=start)
    assert [b["due_date"] for b in x["upcoming_bills"]] == [
        "2026-10-30", "2026-11-30", "2026-12-30", "2027-01-30",
    ]
    assert x["total_bills_due"] == 280


def test_month_end_due_date_clamped_to_february():
    from finance_engine import next_payment_date
    bill = {
        "payee": "Rent", "status": "pending", "payment_date": "2026-01-31",
        "upcoming_payment_date": "2026-01-31", "recurring_date": 31,
        "frequency": "monthly", "payment_amount": 1400,
    }
    assert next_payment_date(bill, date(2026, 2, 1)) == date(2026, 2, 28)
    x = forecast(2000, 0, [bill], horizon_days=65, today=date(2026, 2, 1))
    assert x["upcoming_bills"][0]["due_date"] == "2026-02-28"
    assert x["upcoming_bills"][1]["due_date"] == "2026-03-31"
