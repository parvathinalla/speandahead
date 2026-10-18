import 'package:flutter/material.dart';
import '../../core/api_client/api_client.dart';
import '../../core/auth/auth_service.dart';
import '../../shared/status_badge.dart';

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._() {
    AuthService.instance.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!AuthService.instance.isAuthenticated) {
      // Clear sensitive balances upon logout or token expiry
      _clearBalances();
    } else {
      loadAllData();
    }
    notifyListeners();
  }

  void _clearBalances() {
    checkingBalance = 0;
    savingsBalance = 0;
    jointBalance = 0;
    billsDueTotal = 0;
    shortfallAmount = 0;
    cards = [];
    isLoaded = false;
  }

  bool isLoaded = false;
  bool isLoading = false;
  String? error;
  StatusBadgeType dataSource = StatusBadgeType.demoFixture;

  // Account Balances
  double checkingBalance = 450.00;
  double savingsBalance = 1500.00;
  double jointBalance = 2400.00;

  // Bill Forecast
  double billsDueTotal = 620.00;
  double shortfallAmount = 170.00;
  bool isShortfall = true;
  List<Map<String, dynamic>> upcomingBills = [];

  // Transfer Action State
  bool isTransferExecuting = false;
  Map<String, dynamic>? lastTransferResult;

  // Cards & Recommendations
  List<Map<String, dynamic>> cards = [];
  Map<String, dynamic>? activeCardRecommendation;

  // AutoPay
  double targetUtilizationPct = 29.0;
  double cardBalance = 750.00;
  double cardLimit = 1000.00;
  double theoreticalPaydown = 460.00;
  double maxSafePaymentToday = 250.00;
  bool isFullPaymentAffordable = false;
  bool targetReachable = false;
  String expectedStatementDate = "Oct 23";
  List<Map<String, dynamic>> autopayPlans = [];

  // Joint Account Review
  bool hasPendingJointReview = true;
  Map<String, dynamic>? pendingJointTransaction;
  String? jointReviewDecision;

  // Emergency Readiness
  double emergencyScenarioCost = 1000.00;
  double protectedBills = 1200.00;
  double totalAvailableFunds = 2000.00;
  double usableCashBuffer = 800.00;
  double emergencyGap = 200.00;

  Future<void> loadAllData() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      // 1. Fetch Accounts
      final accountsData = await ApiClient.instance.getAccountsSummary();
      checkingBalance = (accountsData["checking_balance"] as num?)?.toDouble() ?? 450.00;
      savingsBalance = (accountsData["savings_balance"] as num?)?.toDouble() ?? 1500.00;
      jointBalance = (accountsData["joint_balance"] as num?)?.toDouble() ?? 2400.00;

      // 2. Fetch Forecast
      final forecast = await ApiClient.instance.getBillForecast();
      billsDueTotal = (forecast["total_bills_due"] as num?)?.toDouble() ?? 620.00;
      shortfallAmount = (forecast["shortfall_amount"] as num?)?.toDouble() ?? 170.00;
      isShortfall = forecast["is_shortfall"] ?? true;
      upcomingBills = List<Map<String, dynamic>>.from(forecast["upcoming_bills"] ?? []);

      // 3. Fetch Cards
      cards = await ApiClient.instance.getCards();

      // 4. Fetch AutoPay Preview & Plans
      final autopay = await ApiClient.instance.previewAutoPay(targetPct: targetUtilizationPct);
      theoreticalPaydown = (autopay["theoretical_paydown_amount"] as num?)?.toDouble() ?? 460.00;
      maxSafePaymentToday = (autopay["max_safe_payment_today"] as num?)?.toDouble() ?? 250.00;
      isFullPaymentAffordable = autopay["is_full_payment_affordable"] ?? false;
      targetReachable = autopay["target_reachable"] ?? false;
      expectedStatementDate = autopay["expected_statement_date"] ?? "Oct 23";
      autopayPlans = await ApiClient.instance.getAutoPayPlans();

      // 5. Fetch Joint precheck
      final joint = await ApiClient.instance.precheckJoint();
      pendingJointTransaction = joint;
      hasPendingJointReview = joint["requires_partner_review"] ?? true;

      // 6. Fetch Emergency
      final emergency = await ApiClient.instance.evaluateEmergency(cost: emergencyScenarioCost);
      totalAvailableFunds = (emergency["total_available_funds"] as num?)?.toDouble() ?? 2000.00;
      protectedBills = (emergency["protected_committed_bills"] as num?)?.toDouble() ?? 1200.00;
      usableCashBuffer = (emergency["usable_cash_buffer"] as num?)?.toDouble() ?? 800.00;
      emergencyGap = (emergency["potential_gap"] as num?)?.toDouble() ?? 200.00;

      dataSource = (forecast["source"] == "nessie")
          ? StatusBadgeType.liveNessie
          : StatusBadgeType.demoFixture;

      isLoaded = true;
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Execute Guarded Sandbox Savings Transfer
  Future<Map<String, dynamic>> executeSafeTransfer({
    double amount = 170.00,
  }) async {
    isTransferExecuting = true;
    notifyListeners();

    try {
      final res = await ApiClient.instance.confirmTransfer(
        sourceId: "acc_sav_01",
        destinationId: "acc_chk_01",
        amountCents: (amount * 100).toInt(),
      );

      lastTransferResult = res;

      // Update balances locally
      savingsBalance -= amount;
      checkingBalance += amount;
      shortfallAmount = 0.0;
      isShortfall = false;

      notifyListeners();
      return res;
    } finally {
      isTransferExecuting = false;
      notifyListeners();
    }
  }

  // AutoPay configuration
  Future<void> updateAutoPayTarget(double target) async {
    targetUtilizationPct = target;
    final res = await ApiClient.instance.previewAutoPay(targetPct: target);
    theoreticalPaydown = (res["theoretical_paydown_amount"] as num?)?.toDouble() ?? 460.00;
    maxSafePaymentToday = (res["max_safe_payment_today"] as num?)?.toDouble() ?? 250.00;
    isFullPaymentAffordable = res["is_full_payment_affordable"] ?? false;
    targetReachable = res["target_reachable"] ?? false;
    notifyListeners();
  }

  void scheduleAutoPayPlan(double amount) {
    autopayPlans.add({
      "plan_id": "plan_${DateTime.now().millisecondsSinceEpoch}",
      "card_id": "card_ven_01",
      "card_name": "Venture Rewards (•••• 1234)",
      "target_utilization_pct": targetUtilizationPct,
      "payment_amount": amount,
      "scheduled_date": "Oct 22, 2026",
      "status": "scheduled",
      "source": "demo_fixture",
    });
    notifyListeners();
  }

  void cancelAutoPayPlan(String planId) {
    autopayPlans.removeWhere((p) => p["plan_id"] == planId);
    notifyListeners();
  }

  // Joint review actions
  Future<void> submitJointDecision(String reviewId, String decision) async {
    jointReviewDecision = decision;
    hasPendingJointReview = false;
    await ApiClient.instance.submitJointDecision(reviewId: reviewId, decision: decision);
    notifyListeners();
  }

  // Emergency scenario recalculation
  Future<void> recalculateEmergency(double cost) async {
    emergencyScenarioCost = cost;
    final res = await ApiClient.instance.evaluateEmergency(cost: cost);
    usableCashBuffer = (res["usable_cash_buffer"] as num?)?.toDouble() ?? 800.00;
    emergencyGap = (res["potential_gap"] as num?)?.toDouble() ?? 200.00;
    notifyListeners();
  }
}
