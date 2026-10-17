import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 10.0.2.2 for Android emulator, localhost for iOS/desktop/web
  static String baseUrl = "http://127.0.0.1:8000";

  // 1. Bill Forecast
  static Future<Map<String, dynamic>> getBillForecast({
    double checking = 450.0,
    double savings = 1500.0,
    int days = 14,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/bills/forecast"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "checking_balance": checking,
          "savings_balance": savings,
          "horizon_days": days,
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}

    // Graceful offline fixture matching Image 4
    return {
      "checking_balance": checking,
      "total_bills_due": 620.0,
      "shortfall_amount": 170.0,
      "projected_end_balance": -170.0,
      "is_shortfall": true,
      "upcoming_bills": [
        {"name": "Rent (Installment)", "due_date": "Oct 20", "amount": 360.0},
        {"name": "Electricity", "due_date": "Oct 22", "amount": 120.0},
        {"name": "Internet", "due_date": "Oct 25", "amount": 60.0},
        {"name": "Phone", "due_date": "Oct 28", "amount": 80.0},
      ],
      "explanation": "Checking has \$450; upcoming bills total \$620. CreditPilot warns about a \$170 shortfall."
    };
  }

  // 2. Card Evaluation
  static Future<Map<String, dynamic>> evaluateCards({
    double amount = 120.0,
    String category = "groceries",
    String merchant = "Whole Foods",
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/cards/evaluate"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "purchase_amount": amount,
          "purchase_category": category,
          "merchant_name": merchant,
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}

    // Offline fixture matching Image 5
    return {
      "purchase_amount": amount,
      "merchant_name": merchant,
      "recommended_card": {
        "card_name": "Savor One",
        "last4": "5678",
        "reward_rate_pct": 2.0,
        "current_utilization_pct": 25.0,
        "utilization_status": "Healthy range",
        "recommended_reason": "You'll still earn 2% rewards and keep your utilization low, which can help your overall credit health over time."
      },
      "paydown_first_option": 200.0,
      "disclaimer": "This is a suggestion only. We do not guarantee any change to your credit score."
    };
  }

  // 3. Joint Evaluation
  static Future<Map<String, dynamic>> evaluateJoint({
    double amount = 850.0,
    String merchant = "Best Buy",
    String category = "Electronics",
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/joint/evaluate"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "amount": amount,
          "merchant": merchant,
          "category": category,
          "initiator_name": "Alex Smith",
          "partner_name": "Sarah Smith",
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}

    // Offline fixture matching Image 6
    return {
      "is_unusual": true,
      "amount": amount,
      "merchant": merchant,
      "category": category,
      "account_name": "Joint Checking (•••• 4321)",
      "date_time_str": "Today, 10:24 AM",
      "partner_name": "Sarah Smith",
      "requires_partner_confirmation": true,
      "scope_disclaimer": "This works for in-app initiated payments. It does not block all transactions at the bank level."
    };
  }

  // 4. Emergency Evaluation
  static Future<Map<String, dynamic>> evaluateEmergency({
    double checking = 1200.0,
    double savings = 800.0,
    double protectedBills = 1200.0,
    double cost = 1000.0,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/emergency/evaluate"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "checking_balance": checking,
          "savings_balance": savings,
          "protected_bills": protectedBills,
          "emergency_cost": cost,
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}

    // Offline fixture matching Image 7
    return {
      "total_available_funds": checking + savings,
      "protected_committed_bills": protectedBills,
      "usable_cash_buffer": (checking + savings) - protectedBills,
      "estimated_emergency_cost": cost,
      "potential_gap": 200.0,
      "is_gap_present": true,
    };
  }

  // 5. Smart Utilization AutoPay Preview
  static Future<Map<String, dynamic>> getAutoPayPreview({
    double targetPct = 29.0,
    double limit = 1000.0,
    double balance = 750.0,
    double checkingFunds = 600.0,
    double upcomingBills = 250.0,
    double safetyBuffer = 100.0,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/autopay/preview"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "credit_limit": limit,
          "current_balance": balance,
          "target_utilization_pct": targetPct,
          "checking_funds": checkingFunds,
          "upcoming_bills_2weeks": upcomingBills,
          "safety_buffer": safetyBuffer,
          "expected_statement_date": "Oct 23"
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}

    // Offline fixture matching Image 8
    return {
      "card_limit": limit,
      "current_balance": balance,
      "current_utilization_pct": 75.0,
      "target_utilization_pct": targetPct,
      "suggested_paydown_amount": 460.0,
      "checking_funds": checkingFunds,
      "upcoming_bills_2weeks": upcomingBills,
      "safety_buffer": safetyBuffer,
      "max_safe_payment_today": 250.0,
      "is_full_payment_affordable": false,
      "recommended_payment_amount": 250.0,
      "expected_statement_date": "Oct 23",
      "alert_message": "Full \$460 payment is not affordable today. Choose a smaller payment or change the target."
    };
  }
}
