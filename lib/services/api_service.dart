import 'dart:convert';
import 'package:http/http.dart' as http;

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
  static String baseUrl = const String.fromEnvironment(
    'API_BASE_URL', defaultValue: 'http://127.0.0.1:8000');

  /// Set after Auth0 login. Demo backend mode requires no bearer token.
  static String? bearerToken;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (bearerToken != null && bearerToken!.isNotEmpty)
          'Authorization': 'Bearer $bearerToken',
      };

  static Future<Map<String, dynamic>> _request(
      String method, String path, [Map<String, dynamic>? body]) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = method == 'GET'
          ? await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15))
          : await http.post(uri, headers: _headers, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 15));
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
      rethrow;
    } catch (_) {
      throw ApiException('Cannot connect to backend at $baseUrl. '
          'Check that FastAPI is running.');
    }
  }

  static Future<Map<String, dynamic>> health() =>
      _request('GET', '/health');

  static Future<Map<String, dynamic>> getDashboard() =>
      _request('GET', '/api/dashboard');

  static Future<Map<String, dynamic>> getAccounts() =>
      _request('GET', '/api/accounts');

  static Future<Map<String, dynamic>> getBills() =>
      _request('GET', '/api/bills');

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

  static Future<Map<String, dynamic>> explain({
    required String topic, required Map<String, dynamic> result,
  }) => _request('POST', '/api/ai/explain', {
        'topic': topic, 'result': result,
      });
}
