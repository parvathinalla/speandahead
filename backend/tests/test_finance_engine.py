from finance_engine import forecast, card_comparison, autopay_preview, emergency, joint_risk
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

def test_autopay_protected_funds():
    r = autopay_preview(750, 1000, 29, 600, 250, 100)
    assert r["suggested_paydown_amount"] == 460
    assert r["recommended_payment_amount"] == 250
    assert r["auto_execution"] is False

def test_rewards():
    options = {"A":{"balance":750,"credit_limit":1000,"reward_rates":{"groceries":0.03}},
               "B":{"balance":200,"credit_limit":2000,"reward_rates":{"groceries":0.02}}}
    r = card_comparison(options, 120, "groceries")
    assert r["recommended_card"]["card_name"] == "B"

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
    x = forecast(1000, 200, [bill], horizon_days=95, today=start)
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
