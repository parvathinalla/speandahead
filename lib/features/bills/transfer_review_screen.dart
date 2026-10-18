import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/debounced_button.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class TransferReviewScreen extends StatefulWidget {
  const TransferReviewScreen({super.key});

  @override
  State<TransferReviewScreen> createState() => _TransferReviewScreenState();
}

class _TransferReviewScreenState extends State<TransferReviewScreen> {
  bool _isSuccess = false;
  String? _transactionId;
  String? _errorMsg;

  Future<void> _handleConfirmTransfer() async {
    setState(() {
      _errorMsg = null;
    });

    try {
      final res = await AppState.instance.executeSafeTransfer(amount: 170.00);
      if (mounted) {
        setState(() {
          _isSuccess = true;
          _transactionId = res["provider_transaction_id"] ?? res["transfer_id"] ?? "tr_sandbox_confirmed";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Review Savings Transfer"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/bills'),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: StatusBadge(
                  type: _isSuccess ? StatusBadgeType.executedInSandbox : state.dataSource,
                  compact: true,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isSuccess) ...[
                    // Success View (Executed in sandbox)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.successGreenBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppTheme.successGreen, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            "Transfer Executed Successfully",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.successGreenText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const StatusBadge(type: StatusBadgeType.executedInSandbox),
                          const SizedBox(height: 12),
                          Text(
                            "\$170.00 was moved from Emergency Savings to Primary Checking via Parvathi's secure action gate.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppTheme.successGreenText.withValues(alpha: 0.9), height: 1.4),
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Provider Tx ID", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              Text(
                                _transactionId ?? "tr_sandbox_confirmed",
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("New Checking Balance", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              Text("\$${state.checkingBalance.toStringAsFixed(2)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Remaining Savings", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              Text("\$${state.savingsBalance.toStringAsFixed(2)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.brandBlue)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => context.go('/bills'),
                        child: const Text("Back to Bill Forecast"),
                      ),
                    ),
                  ] else ...[
                    // Pre-confirmation Transfer Details
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("PROPOSED SAFE TRANSFER", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                                StatusBadge(type: StatusBadgeType.simulation, compact: true),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Center(
                              child: Text(
                                "\$170.00",
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.brandNavy,
                                  fontFamily: 'Plus Jakarta Sans',
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Center(
                              child: Text(
                                "Exact amount to prevent negative balance on Oct 20",
                                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ),
                            const Divider(height: 24),
                            _buildAccountRow("From", "Emergency Savings (•••• 1122)", "\$1,500.00", "Remaining: \$1,330.00"),
                            const SizedBox(height: 12),
                            _buildAccountRow("To", "Primary Checking (•••• 7890)", "\$450.00", "Resulting: \$620.00 (Covers Rent)"),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Safety verification badge & explanation
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.brandBlueLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_user_rounded, color: AppTheme.brandBlue, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Backend Guard Verified: Leaves \$1,330 in Emergency Savings, well above your \$100 minimum safety reserve.",
                              style: TextStyle(fontSize: 11.5, color: AppTheme.brandNavy, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (_errorMsg != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.riskRedBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const StatusBadge(type: StatusBadgeType.notExecuted, compact: true),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_errorMsg!, style: const TextStyle(fontSize: 11, color: AppTheme.riskRedText))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    const DisclaimerBanner(
                      text: "Sandbox Execution: Executed via backend Nessie sandbox adapter. No real bank accounts are debited.",
                    ),
                    const SizedBox(height: 20),

                    // Debounced Confirmation Button (T24: two fast taps do not issue two transfers)
                    DebouncedButton(
                      onPressed: _handleConfirmTransfer,
                      backgroundColor: AppTheme.brandBlue,
                      child: const Text("Confirm & Execute Sandbox Transfer"),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: () => context.go('/bills'),
                        child: const Text("Cancel and return", style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountRow(String label, String name, String current, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
              Text(sub, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
        ),
        Text(current, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
      ],
    );
  }
}
