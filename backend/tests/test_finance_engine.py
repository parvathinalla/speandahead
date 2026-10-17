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
