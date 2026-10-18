import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class JointScreen extends StatelessWidget {
  const JointScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Screen Header
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.brandBlueLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.people, color: AppTheme.brandBlue),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Joint Account Check",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.brandNavy,
                                fontFamily: 'Plus Jakarta Sans',
                              ),
                            ),
                            Text(
                              "Get a heads up on unusual in-app payments from your joint account.",
                              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      StatusBadge(
                        type: state.hasPendingJointReview ? StatusBadgeType.pendingReview : StatusBadgeType.demoFixture,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Account Summary Pill
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Joint Checking (•••• 4321)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                              SizedBox(height: 2),
                              Text("Co-Owners: Alex Smith & Sarah Smith", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                            ],
                          ),
                          Text(
                            "\$${state.jointBalance.toStringAsFixed(0)}",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.brandNavy),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (state.hasPendingJointReview) ...[
                    // Unusual Payment Detected Banner ($850 Best Buy)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.riskRedBg,
                        borderRadius: BorderRadius.circular(14),
                        border: const Border(left: BorderSide(color: AppTheme.riskRed, width: 4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: AppTheme.riskRed, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Unusual Payment Detected", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.riskRedText)),
                                Text("\$850.00", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.riskRed)),
                                Text("at Best Buy • Today, 10:24 AM", style: TextStyle(fontSize: 11, color: AppTheme.riskRedText)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info, size: 14, color: Color(0xFF0369A1)),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Reason: Amount is higher than usual for this account & merchant is in a new category.",
                              style: TextStyle(fontSize: 11, color: Color(0xFF0369A1), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Transaction details table
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            _buildRow(Icons.storefront, "Merchant", "Best Buy"),
                            const Divider(height: 16),
                            _buildRow(Icons.credit_card, "Amount", "\$850.00"),
                            const Divider(height: 16),
                            _buildRow(Icons.access_time, "Date & Time", "Oct 17, 2026, 10:24 AM"),
                            const Divider(height: 16),
                            _buildRow(Icons.label_outline, "Category", "Electronics"),
                            const Divider(height: 16),
                            _buildRow(Icons.person_outline, "Initiated by", "Alex Smith"),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Partner Confirmation Prompt
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 20,
                              backgroundColor: AppTheme.brandBlueLight,
                              child: Icon(Icons.person, color: AppTheme.brandNavy),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Partner Confirmation Required", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                                  Text("Sarah Smith must approve or discuss this in-app initiated payment.", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.rate_review_rounded, size: 18),
                        label: const Text("Open Partner Decision Review"),
                        onPressed: () => context.go('/joint/review/rev_joint_850_01'),
                      ),
                    ),
                  ] else ...[
                    // Decision already resolved view
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.successGreenBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppTheme.successGreen, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                "Payment Decision: ${state.jointReviewDecision?.toUpperCase() ?? "APPROVED"}",
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.successGreenText),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "The \$850 Best Buy payment check was resolved by partner consensus. In-app transaction status updated.",
                            style: TextStyle(fontSize: 11.5, color: AppTheme.successGreenText),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Button to initiate a new transfer precheck
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text("Pre-check New Joint Transfer"),
                      onPressed: () => context.go('/joint/new'),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const DisclaimerBanner(
                    text:
                        "Scope Disclaimer: CreditPilot monitors in-app initiated payments. It does NOT claim to block or intercept outside transactions at the bank level.",
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(IconData icon, String label, String val) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.brandNavy),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
        const Spacer(),
        Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
      ],
    );
  }
}
