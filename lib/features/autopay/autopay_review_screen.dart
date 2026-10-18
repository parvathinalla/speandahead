import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/debounced_button.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class AutoPayReviewScreen extends StatefulWidget {
  const AutoPayReviewScreen({super.key});

  @override
  State<AutoPayReviewScreen> createState() => _AutoPayReviewScreenState();
}

class _AutoPayReviewScreenState extends State<AutoPayReviewScreen> {
  bool _hasConsented = false;
  bool _isScheduled = false;

  Future<void> _handleSchedule() async {
    await Future.delayed(const Duration(milliseconds: 400));
    AppState.instance.scheduleAutoPayPlan(250.00);
    if (mounted) {
      setState(() => _isScheduled = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        //final state = AppState.instance;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Confirm AutoPay Plan"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/cards/autopay'),
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 12),
                child: StatusBadge(type: StatusBadgeType.simulation, compact: true),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isScheduled) ...[
                    // Success View
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
                            "Smart AutoPay Plan Scheduled",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.successGreenText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const StatusBadge(type: StatusBadgeType.simulation),
                          const SizedBox(height: 12),
                          const Text(
                            "An early paydown of \$250.00 will be initiated on Oct 22, 2026 (prior to estimated statement date Oct 23) to keep utilization at 50%.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppTheme.successGreenText, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => context.go('/cards/autopay/plans'),
                        child: const Text("View All Active Plans"),
                      ),
                    ),
                  ] else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("PLAN SUMMARY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                            const SizedBox(height: 12),
                            const Center(
                              child: Text(
                                "\$250.00",
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.brandNavy,
                                  fontFamily: 'Plus Jakarta Sans',
                                ),
                              ),
                            ),
                            const Center(
                              child: Text(
                                "Safe Payment Today (Target 29% partial)",
                                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ),
                            const Divider(height: 24),
                            _buildSummaryRow("Target Card", "Venture Rewards (•••• 1234)"),
                            const SizedBox(height: 8),
                            _buildSummaryRow("Funding Source", "Primary Checking (•••• 7890)"),
                            const SizedBox(height: 8),
                            _buildSummaryRow("Execution Date", "Oct 22, 2026 (1 day before est. close)"),
                            const SizedBox(height: 8),
                            _buildSummaryRow("Resulting Utilization", "50% (reduced from 75%)"),
                            const SizedBox(height: 8),
                            _buildSummaryRow("Remaining Checking", "\$350.00 (bills + \$100 buffer preserved)"),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Explicit user consent check
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _hasConsented,
                            activeColor: AppTheme.brandBlue,
                            onChanged: (val) => setState(() => _hasConsented = val ?? false),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _hasConsented = !_hasConsented),
                              child: const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  "I explicitly consent to CreditPilot planning this \$250.00 payment from my Primary Checking account. I understand this is an in-app plan and dates are estimates.",
                                  style: TextStyle(fontSize: 11, color: AppTheme.brandNavy, height: 1.35),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    const DisclaimerBanner(
                      text: "Out-of-scope note: CreditPilot does not integrate directly with third-party card issuer autopay or credit bureau reporting APIs.",
                    ),
                    const SizedBox(height: 20),

                    DebouncedButton(
                      enabled: _hasConsented,
                      onPressed: _handleSchedule,
                      backgroundColor: AppTheme.brandBlue,
                      child: const Text("Schedule Safe AutoPay Plan"),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: () => context.go('/cards/autopay'),
                        child: const Text("Back to AutoPay Settings", style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
      ],
    );
  }
}
