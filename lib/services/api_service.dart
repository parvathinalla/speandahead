import '../core/api_client/api_client.dart';

class ApiService {
  static String get baseUrl => ApiClient.instance.baseUrl;
  static set baseUrl(String val) => ApiClient.instance.baseUrl = val;

  static Future<Map<String, dynamic>> getBillForecast({
    double checking = 450.0,
    double savings = 1500.0,
    int days = 14,
  }) =>
      ApiClient.instance.getBillForecast(horizon: days);

  static Future<Map<String, dynamic>> evaluateCards({
    double amount = 120.0,
    String category = "groceries",
    String merchant = "Whole Foods",
  }) =>
      ApiClient.instance.recommendCard(amount: amount, category: category, merchant: merchant);

  static Future<Map<String, dynamic>> evaluateJoint({
    double amount = 850.0,
    String merchant = "Best Buy",
    String category = "Electronics",
  }) =>
      ApiClient.instance.precheckJoint(amount: amount, merchant: merchant);

  static Future<Map<String, dynamic>> evaluateEmergency({
    double checking = 1200.0,
    double savings = 800.0,
    double protectedBills = 1200.0,
    double cost = 1000.0,
  }) =>
      ApiClient.instance.evaluateEmergency(cost: cost);

  static Future<Map<String, dynamic>> getAutoPayPreview({
    double targetPct = 29.0,
    double limit = 1000.0,
    double balance = 750.0,
    double checkingFunds = 600.0,
    double upcomingBills = 250.0,
    double safetyBuffer = 100.0,
  }) =>
      ApiClient.instance.previewAutoPay(targetPct: targetPct);
}
