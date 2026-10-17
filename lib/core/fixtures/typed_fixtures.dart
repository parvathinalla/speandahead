class TypedFixtures {
  static const String sourceNessie = "nessie";
  static const String sourceFixture = "demo_fixture";

  // 1. Demo Profile
  static Map<String, dynamic> getDemoProfile() {
    return {
      "user_id": "usr_alex_smith_01",
      "display_name": "Alex Smith",
      "email": "alex.smith@example.com",
      "partner_name": "Sarah Smith",
      "partner_email": "sarah.smith@example.com",
      "joint_account_id": "acc_joint_01",
      "roles": ["owner", "primary_borrower"],
      "source": sourceFixture,
      "fetched_at": DateTime.now().toUtc().toIso8601String(),
    };
  }

  // 2. Accounts Summary
  static Map<String, dynamic> getAccountsSummary() {
    return {
      "checking_balance": 450.00,
      "savings_balance": 1500.00,
      "joint_balance": 2400.00,
      "currency": "USD",
      "source": sourceFixture,
      "accounts": [
        {
          "account_id": "acc_chk_01",
          "nickname": "Primary Checking",
          "type": "Checking",
          "masked_number": "•••• 7890",
          "balance": 450.00,
          "balance_cents": 45000,
          "is_joint": false,
        },
        {
          "account_id": "acc_sav_01",
          "nickname": "Emergency Savings",
          "type": "Savings",
          "masked_number": "•••• 1122",
          "balance": 1500.00,
          "balance_cents": 150000,
          "is_joint": false,
        },
        {
          "account_id": "acc_joint_01",
          "nickname": "Joint Checking",
          "type": "Checking",
          "masked_number": "•••• 4321",
          "balance": 2400.00,
          "balance_cents": 240000,
          "is_joint": true,
          "partner_name": "Sarah Smith",
        },
      ],
      "fetched_at": DateTime.now().toUtc().toIso8601String(),
    };
  }

  // 3. Bill Forecast (14-day)
  static Map<String, dynamic> getBillForecast({
    double checking = 450.0,
    int horizon = 14,
  }) {
    return {
      "checking_balance": checking,
      "total_bills_due": 620.00,
      "shortfall_amount": 170.00,
      "projected_end_balance": -170.00,
      "is_shortfall": true,
      "horizon_days": horizon,
      "source": sourceFixture,
      "upcoming_bills": [
        {
          "bill_id": "bill_01",
          "name": "Rent (Installment)",
          "due_date": "Oct 20",
          "amount": 360.00,
          "amount_cents": 36000,
          "category": "Housing",
          "is_essential": true,
        },
        {
          "bill_id": "bill_02",
          "name": "Electricity",
          "due_date": "Oct 22",
          "amount": 120.00,
          "amount_cents": 12000,
          "category": "Utilities",
          "is_essential": true,
        },
        {
          "bill_id": "bill_03",
          "name": "Internet",
          "due_date": "Oct 25",
          "amount": 60.00,
          "amount_cents": 6000,
          "category": "Utilities",
          "is_essential": true,
        },
        {
          "bill_id": "bill_04",
          "name": "Phone",
          "due_date": "Oct 28",
          "amount": 80.00,
          "amount_cents": 8000,
          "category": "Telecommunications",
          "is_essential": true,
        },
      ],
      "explanation": "Checking has \$450; upcoming bills total \$620. CreditPilot warns about a \$170 shortfall before Oct 20.",
      "fetched_at": DateTime.now().toUtc().toIso8601String(),
    };
  }

  // 4. Savings Transfer Option
  static Map<String, dynamic> getSavingsTransferOption() {
    return {
      "is_safe": true,
      "recommended_transfer_amount": 170.00,
      "source_account_id": "acc_sav_01",
      "source_name": "Emergency Savings (•••• 1122)",
      "destination_account_id": "acc_chk_01",
      "destination_name": "Primary Checking (•••• 7890)",
      "current_savings_balance": 1500.00,
      "remaining_savings_balance": 1330.00,
      "target_checking_balance_after": 620.00,
      "source": sourceFixture,
      "fetched_at": DateTime.now().toUtc().toIso8601String(),
    };
  }

  // 5. Cards Inventory
  static List<Map<String, dynamic>> getCards() {
    return [
      {
        "card_id": "card_ven_01",
        "name": "Venture Rewards",
        "last4": "1234",
        "network": "VISA",
        "credit_limit": 1000.00,
        "current_balance": 750.00,
        "utilization_pct": 75.0,
        "status_label": "High utilization",
        "is_high_utilization": true,
        "reward_rate_pct": 3.0,
        "expected_statement_date": "Oct 23",
        "is_demo_modeled": true,
      },
      {
        "card_id": "card_sav_01",
        "name": "Savor One",
        "last4": "5678",
        "network": "VISA",
        "credit_limit": 1000.00,
        "current_balance": 250.00,
        "utilization_pct": 25.0,
        "status_label": "Healthy range",
        "is_high_utilization": false,
        "reward_rate_pct": 2.0,
        "expected_statement_date": "Oct 28",
        "is_demo_modeled": true,
      },
    ];
  }

  // 6. Card Recommendation (for purchase evaluation)
  static Map<String, dynamic> getCardRecommendation({
    double amount = 120.0,
    String merchant = "Whole Foods",
    String category = "groceries",
  }) {
    return {
      "purchase_amount": amount,
      "merchant_name": merchant,
      "purchase_category": category,
      "source": sourceFixture,
      "cards_evaluated": [
        {
          "card_id": "card_ven_01",
          "name": "Venture Rewards •••• 1234",
          "reward_rate_pct": 3.0,
          "reward_dollars": 3.60,
          "utilization_before": 75.0,
          "utilization_after": 87.0,
          "status_label": "High utilization",
          "is_warning": true,
        },
        {
          "card_id": "card_sav_01",
          "name": "Savor One •••• 5678",
          "reward_rate_pct": 2.0,
          "reward_dollars": 2.40,
          "utilization_before": 25.0,
          "utilization_after": 37.0,
          "status_label": "Healthy range",
          "is_warning": false,
        },
      ],
      "recommended_card_id": "card_sav_01",
      "recommended_card_name": "Savor One (Card B)",
      "recommended_reason":
          "You'll still earn 2% rewards (\$2.40) and keep your utilization healthy (37% vs 87%), which can help your overall credit profile over time.",
      "paydown_first_option": 200.00,
      "disclaimer": "This is a suggestion only. We do not guarantee any change to your credit score.",
      "fetched_at": DateTime.now().toUtc().toIso8601String(),
    };
  }

  // 7. AutoPay Preview
  static Map<String, dynamic> getAutoPayPreview({
    double targetPct = 29.0,
  }) {
    return {
      "card_limit": 1000.00,
      "current_balance": 750.00,
      "current_utilization_pct": 75.0,
      "target_utilization_pct": targetPct,
      "theoretical_paydown_amount": 460.00,
      "checking_funds": 600.00,
      "upcoming_bills_2weeks": 250.00,
      "safety_buffer": 100.00,
      "max_safe_payment_today": 250.00,
      "is_full_payment_affordable": false,
      "target_reachable": false,
      "recommended_payment_amount": 250.00,
      "resulting_balance": 500.00,
      "resulting_utilization_pct": 50.0,
      "expected_statement_date": "Oct 23",
      "is_statement_date_estimate": true,
      "alert_message":
          "Target 29% is not reachable safely today. Safe payment of \$250 leaves \$500 balance (50% utilization).",
      "reason_code": "TARGET_NOT_AFFORDABLE",
      "source": sourceFixture,
      "fetched_at": DateTime.now().toUtc().toIso8601String(),
    };
  }

  // 8. Joint Account Evaluation
  static Map<String, dynamic> getJointEvaluation({
    double amount = 850.0,
    String merchant = "Best Buy",
  }) {
    return {
      "review_id": "rev_joint_850_01",
      "is_unusual": true,
      "amount": amount,
      "merchant": merchant,
      "category": "Electronics",
      "account_name": "Joint Checking (•••• 4321)",
      "date_time_str": "Oct 17, 2026, 10:24 AM",
      "initiator_name": "Alex Smith",
      "partner_name": "Sarah Smith",
      "requires_partner_review": true,
      "reason_code": "NEW_RECIPIENT_AND_AMOUNT_ABOVE_THRESHOLD",
      "explanation": "This amount (\$850) is higher than normal for this account and merchant is newly flagged.",
      "scope_disclaimer":
          "Monitors in-app initiated transactions. This does not block all transactions at the bank level.",
      "source": sourceFixture,
      "status": "pending_review",
      "fetched_at": DateTime.now().toUtc().toIso8601String(),
    };
  }

  // 9. Emergency Readiness
  static Map<String, dynamic> getEmergencyEvaluation({
    double cost = 1000.0,
    double checking = 1200.0,
    double savings = 800.0,
    double protectedBills = 1200.0,
  }) {
    final totalFunds = checking + savings; // 2000
    final usableBuffer = totalFunds - protectedBills; // 800
    final gap = cost > usableBuffer ? cost - usableBuffer : 0.0; // 200

    return {
      "total_available_funds": totalFunds,
      "checking_funds": checking,
      "savings_funds": savings,
      "protected_committed_bills": protectedBills,
      "usable_cash_buffer": usableBuffer,
      "estimated_emergency_cost": cost,
      "potential_gap": gap,
      "is_gap_present": gap > 0,
      "suggested_actions": [
        "Move money from secondary savings",
        "Pause non-essential monthly subscriptions",
        "Explore an authorized short-term buffer",
      ],
      "disclaimer": "Scenario costs are user estimates. Emergency evaluations do not guarantee reimbursement.",
      "source": sourceFixture,
      "fetched_at": DateTime.now().toUtc().toIso8601String(),
    };
  }
}
