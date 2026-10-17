import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth/auth_service.dart';
import '../fixtures/typed_fixtures.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._();
  ApiClient._();

  String baseUrl = "http://127.0.0.1:8000";
  final http.Client _client = http.Client();
  final Duration timeout = const Duration(seconds: 4);

  Map<String, String> _headers() {
    final headers = {
      "Content-Type": "application/json",
      "Accept": "application/json",
    };
    final token = AuthService.instance.token;
    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }
    return headers;
  }

  // 1. Demo Profile
  Future<Map<String, dynamic>> getDemoProfile() async {
    try {
      final res = await _client
          .get(Uri.parse("$baseUrl/v1/demo/profile"), headers: _headers())
          .timeout(timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return TypedFixtures.getDemoProfile();
  }

  // 2. Accounts Summary
  Future<Map<String, dynamic>> getAccountsSummary() async {
    try {
      final res = await _client
          .get(Uri.parse("$baseUrl/v1/accounts/summary"), headers: _headers())
          .timeout(timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return TypedFixtures.getAccountsSummary();
  }

  // 3. Bill Forecast
  Future<Map<String, dynamic>> getBillForecast({int horizon = 14}) async {
    try {
      final res = await _client
          .get(Uri.parse("$baseUrl/v1/bills/forecast?horizon=$horizon"), headers: _headers())
          .timeout(timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return TypedFixtures.getBillForecast(horizon: horizon);
  }

  // 4. Savings Transfer Option
  Future<Map<String, dynamic>> getSavingsTransferOptions({
    String sourceId = "acc_sav_01",
    String targetId = "acc_chk_01",
    int amountCents = 17000,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse("$baseUrl/v1/bills/savings-options"),
            headers: _headers(),
            body: jsonEncode({
              "source_id": sourceId,
              "target_id": targetId,
              "amount_cents": amountCents,
            }),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return TypedFixtures.getSavingsTransferOption();
  }

  // 5. Transfer Confirmation (Guarded Sandbox Action)
  Future<Map<String, dynamic>> confirmTransfer({
    required String sourceId,
    required String destinationId,
    required int amountCents,
    String? idempotencyKey,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse("$baseUrl/v1/actions/transfers/confirm"),
            headers: _headers(),
            body: jsonEncode({
              "source_id": sourceId,
              "destination_id": destinationId,
              "amount_cents": amountCents,
              "idempotency_key": idempotencyKey ?? "idemp_${DateTime.now().millisecondsSinceEpoch}",
            }),
          )
          .timeout(timeout);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body);
      }
    } catch (_) {}

    // Simulated sandbox execution fallback
    await Future.delayed(const Duration(milliseconds: 600));
    final dollars = (amountCents / 100.0).toStringAsFixed(2);
    return {
      "success": true,
      "provider_transaction_id": "tr_nessie_sandbox_${DateTime.now().millisecondsSinceEpoch}",
      "status": "executed",
      "amount": double.parse(dollars),
      "amount_cents": amountCents,
      "source_id": sourceId,
      "destination_id": destinationId,
      "source": "demo_fixture",
      "executed_in_sandbox": true,
      "message": "Transfer of \$$dollars executed in sandbox.",
      "executed_at": DateTime.now().toUtc().toIso8601String(),
    };
  }

  // 6. Cards Inventory
  Future<List<Map<String, dynamic>>> getCards() async {
    try {
      final res = await _client
          .get(Uri.parse("$baseUrl/v1/cards"), headers: _headers())
          .timeout(timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(decoded);
        }
      }
    } catch (_) {}
    return TypedFixtures.getCards();
  }

  // 7. Card Recommendation
  Future<Map<String, dynamic>> recommendCard({
    double amount = 120.0,
    String merchant = "Whole Foods",
    String category = "groceries",
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse("$baseUrl/v1/cards/recommend"),
            headers: _headers(),
            body: jsonEncode({
              "purchase_amount": amount,
              "merchant_name": merchant,
              "category": category,
            }),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return TypedFixtures.getCardRecommendation(amount: amount, merchant: merchant, category: category);
  }

  // 8. AutoPay Preview
  Future<Map<String, dynamic>> previewAutoPay({
    double targetPct = 29.0,
    String cardId = "card_ven_01",
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse("$baseUrl/v1/cards/autopay/preview"),
            headers: _headers(),
            body: jsonEncode({
              "target_utilization_pct": targetPct,
              "card_id": cardId,
            }),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return TypedFixtures.getAutoPayPreview(targetPct: targetPct);
  }

  // 9. AutoPay Plans
  Future<List<Map<String, dynamic>>> getAutoPayPlans() async {
    try {
      final res = await _client
          .get(Uri.parse("$baseUrl/v1/cards/autopay/plans"), headers: _headers())
          .timeout(timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(decoded);
        }
      }
    } catch (_) {}
    return [
      {
        "plan_id": "plan_01",
        "card_id": "card_ven_01",
        "card_name": "Venture Rewards (•••• 1234)",
        "target_utilization_pct": 29.0,
        "payment_amount": 250.00,
        "scheduled_date": "Oct 22, 2026",
        "status": "active",
        "source": "demo_fixture",
      }
    ];
  }

  // 10. Joint Payment Pre-check
  Future<Map<String, dynamic>> precheckJoint({
    double amount = 850.0,
    String merchant = "Best Buy",
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse("$baseUrl/v1/joint/precheck"),
            headers: _headers(),
            body: jsonEncode({
              "amount": amount,
              "merchant": merchant,
            }),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return TypedFixtures.getJointEvaluation(amount: amount, merchant: merchant);
  }

  // 11. Joint Review Decision
  Future<Map<String, dynamic>> submitJointDecision({
    required String reviewId,
    required String decision, // "approved", "declined", "discussion_requested"
    String? note,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse("$baseUrl/v1/joint/reviews/$reviewId/decision"),
            headers: _headers(),
            body: jsonEncode({
              "decision": decision,
              "note": note ?? "",
            }),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return {
      "review_id": reviewId,
      "decision": decision,
      "status": "resolved",
      "timestamp": DateTime.now().toUtc().toIso8601String(),
    };
  }

  // 12. Emergency Evaluation
  Future<Map<String, dynamic>> evaluateEmergency({
    double cost = 1000.0,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse("$baseUrl/v1/emergency/evaluate"),
            headers: _headers(),
            body: jsonEncode({
              "emergency_cost": cost,
            }),
          )
          .timeout(timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return TypedFixtures.getEmergencyEvaluation(cost: cost);
  }
}
