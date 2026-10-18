import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../auth/auth_config.dart';

/// All banking credentials stay in FastAPI; Flutter never calls Nessie directly.
/// Run Web/Windows: flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
/// Android emulator: replace 127.0.0.1 with 10.0.2.2.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ApiService {
  static final String baseUrl = const String.fromEnvironment(
    'API_BASE_URL', defaultValue: 'http://127.0.0.1:8000');

  // Auth0 SDK securely manages the session. Always retrieve a fresh access
  // token; do not persist or copy long-lived credentials into Flutter state.
  static Future<String?> Function()? tokenProvider;

  static Future<Map<String, dynamic>> _request(
      String method, String path, [Map<String, dynamic>? body,
        Map<String, String>? extraHeaders]) async {
    try {
      if (kReleaseMode && Uri.parse(baseUrl).scheme != 'https') {
        throw ApiException(
          'Release builds require HTTPS for protected API calls.');
      }
      final uri = Uri.parse('$baseUrl$path');
      final accessToken = await tokenProvider?.call();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (accessToken != null && accessToken.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
        if (extraHeaders != null) ...extraHeaders,
      };
      final response = method == 'GET'
          ? await http.get(uri, headers: headers).timeout(const Duration(seconds: 30))
          : await http.post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 30));
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw ApiException('Backend returned an invalid response.',
            statusCode: response.statusCode);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'API ' + response.statusCode.toString() + ': ' +
              (payload['detail']?.toString() ?? 'Request failed'),
          statusCode: response.statusCode);
      }
      return payload;
    } on ApiException {
      rethrow; // Preserve backend HTTP status such as 503.
    } on TimeoutException {
      throw ApiException('Backend took too long at $baseUrl. '
          'Nessie may be temporarily slow. Tap Retry.');
    } on http.ClientException {
      throw ApiException('Browser could not reach $baseUrl. '
          'Open $baseUrl/health in Chrome. If /health works, '
          'check CORS_ORIGINS in backend/.env.');
    } catch (error) {
      throw ApiException('Unexpected API error ($error). '
          'See Chrome developer tools and FastAPI terminal.');
    }
  }

  static Future<Map<String, dynamic>> health() =>
      _request('GET', '/health');

  static Future<Map<String, dynamic>> me() =>
      _request('GET', '/api/me');

  static Future<Map<String, dynamic>> getDashboard() =>
      _request('GET', '/api/dashboard');

  static Future<Map<String, dynamic>> getAccounts() =>
      _request('GET', '/api/accounts');

  static Future<Map<String, dynamic>> getBills() =>
      _request('GET', '/api/bills');

  static Future<Map<String, dynamic>> getDemoCatalog() =>
      _request('GET', '/api/demo/catalog');

  static Future<Map<String, dynamic>> getBankingProfile() =>
      _request('GET', '/api/profile');

  static Future<Map<String, dynamic>> updateMonthlyIncome(double income) =>
      _request('POST', '/api/profile/income', {'monthly_income': income});

  static Future<Map<String, dynamic>> getCardCatalog() =>
      _request('GET', '/api/cards/catalog');

  static Future<Map<String, dynamic>> getTransactions({
    int limit = 50, int offset = 0,
  }) => _request('GET', '/api/transactions?limit=$limit&offset=$offset');

  static Future<Map<String, dynamic>> createBill({
    required String payee, required double amount, required String dueDate,
    String category = 'other', String frequency = 'monthly',
  }) => _request('POST', '/api/bills/create', {
        'payee': payee, 'payment_amount': amount,
        'payment_date': dueDate, 'category': category,
        'frequency': frequency,
      });

  static Future<Map<String, dynamic>> updateBill({
    required String billId, required String payee,
    required double amount, required String dueDate,
    String category = 'other', String frequency = 'monthly',
  }) => _request('POST', '/api/bills/$billId/update', {
        'payee': payee, 'payment_amount': amount,
        'payment_date': dueDate, 'category': category,
        'frequency': frequency,
      });

  static Future<Map<String, dynamic>> deleteBill({
    required String billId,
  }) => _request('POST', '/api/bills/$billId/delete');

  static Future<Map<String, dynamic>> getBillForecast({
    int days = 14, double protectedReserve = 0,
  }) => _request('POST', '/api/bills/forecast', {
        'horizon_days': days, 'protected_reserve': protectedReserve,
      });

  static Future<Map<String, dynamic>> evaluateCards({
    double amount = 120, String category = 'groceries',
    String merchant = 'Grocery store', double targetPct = 30,
  }) => _request('POST', '/api/cards/evaluate', {
        'purchase_amount': amount,
        'purchase_category': category,
        'merchant_name': merchant,
        'utilization_target_pct': targetPct,
      });

  static Future<Map<String, dynamic>> evaluateJoint({
    double amount = 850, String merchant = 'Electronics Store',
    String category = 'Shopping',
  }) => _request('POST', '/api/joint/evaluate', {
        'amount': amount, 'merchant': merchant, 'category': category,
      });

  static Future<Map<String, dynamic>> requestJointApproval({
    required double amount, required String merchant,
  }) => _request('POST', '/api/joint/proposals', {
        'amount': amount, 'merchant': merchant, 'confirmed': true,
      });

  static Future<Map<String, dynamic>> getJointInvitations() =>
      _request('GET', '/api/joint/invitations');

  static Future<Map<String, dynamic>> getMyJointProposals() =>
      _request('GET', '/api/joint/proposals');

  static Future<Map<String, dynamic>> decideJointProposal({
    required String proposalId, required bool approve,
  }) => _request(
      'POST', '/api/joint/proposals/' + proposalId + '/decision',
      {'approve': approve},
      AuthConfig.debugDemo ? {'X-Demo-User': 'jamie'} : null);

  static Future<Map<String, dynamic>> evaluateEmergency({
    double cost = 1000, double buffer = 300, int days = 14,
  }) => _request('POST', '/api/emergency/evaluate', {
        'emergency_cost': cost, 'safety_buffer': buffer, 'horizon_days': days,
      });

  static Future<Map<String, dynamic>> getAutoPayPreview({
    double targetPct = 29, String account = 'card_a',
    double safetyBuffer = 100, double assumedSavingsTransfer = 0,
  }) => _request('POST', '/api/autopay/preview', {
        'target_utilization_pct': targetPct,
        'account': account, 'safety_buffer': safetyBuffer,
        'assumed_savings_transfer': assumedSavingsTransfer,
      });

  static Future<Map<String, dynamic>> scheduleAutoPay({
    double targetPct = 29, String account = 'card_a',
    double safetyBuffer = 100, double assumedSavingsTransfer = 0,
  }) => _request('POST', '/api/autopay/plans', {
        'target_utilization_pct': targetPct,
        'account': account, 'safety_buffer': safetyBuffer,
        'assumed_savings_transfer': assumedSavingsTransfer,
        'confirmed': true,
      });

  static Future<Map<String, dynamic>> transferPreview({
    required double amount, required String idempotencyKey,
  }) => _request('POST', '/api/transfers/preview', {
        'amount': amount, 'idempotency_key': idempotencyKey,
      });

  static Future<Map<String, dynamic>> executeTransfer({
    required double amount, required String idempotencyKey,
  }) => _request('POST', '/api/transfers/execute', {
        'amount': amount, 'idempotency_key': idempotencyKey,
        'confirmed': true,
      });

  static Future<Map<String, dynamic>> simulatePurchase({
    required double amount, required String category,
    double? emergencyCost,
  }) => _request('POST', '/api/decisions/purchase', {
        'purchase_amount': amount,
        'purchase_category': category,
        if (emergencyCost != null) 'emergency_cost': emergencyCost,
      });

  /// Personalized agent. The backend independently loads the signed-in
  /// user's financial sandbox; clients cannot submit arbitrary balances.
  static Future<Map<String, dynamic>> agentChat(String message) =>
      _request('POST', '/api/agent/chat', {'message': message});

  static Future<Map<String, dynamic>> agentSettings() =>
      _request('GET', '/api/agent/settings');

  static Future<Map<String, dynamic>> agentConsent(bool enabled) =>
      _request('POST', '/api/agent/settings', {'enabled': enabled});

  static Future<Map<String, dynamic>> agentMemories() =>
      _request('GET', '/api/agent/memories');

  static Future<Map<String, dynamic>> agentHistory() =>
      _request('GET', '/api/agent/history');

  static Future<Map<String, dynamic>> rememberPreference(String note) =>
      _request('POST', '/api/agent/memories', {'note': note});

  static Future<Map<String, dynamic>> deletePreference(String id) =>
      _request('POST', '/api/agent/memories/$id/delete');

  static Future<Map<String, dynamic>> clearAgentMemory() =>
      _request('POST', '/api/agent/memories/clear');

  static Future<Map<String, dynamic>> explain({
    required String topic, required Map<String, dynamic> result,
  }) => _request('POST', '/api/ai/explain', {
        'topic': topic, 'result': result,
      });
}
