import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        final availableFunds = state.totalAvailableFunds; // $2,000
        final protectedBills = state.protectedBills; // $1,200
        final emergencyCost = state.emergencyScenarioCost; // $1,000
        final usableBuffer = state.usableCashBuffer; // $800
        final gap = state.emergencyGap; // $200

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
                        child: const Icon(Icons.shield_outlined, color: AppTheme.brandBlue),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Emergency Readiness",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.brandNavy,
                                fontFamily: 'Plus Jakarta Sans',
                              ),
                            ),
                            Text(
                              "See if your current funds can cover an unexpected emergency.",
                              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const StatusBadge(type: StatusBadgeType.demoFixture, compact: true),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Hero Explanation Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.brandBlueLight,
                            ),
                            child: const Icon(Icons.beach_access, color: AppTheme.brandBlue, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Can your funds cover an emergency?",
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Based on liquid accounts minus committed bills over your forecast window.",
                                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Funds & Bills Breakdown Table
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _buildBreakdownRow(Icons.account_balance_wallet, "Available funds", "(Checking + Savings)", "\$${availableFunds.toStringAsFixed(0)}"),
                          const Divider(height: 20),
                          _buildBreakdownRow(Icons.description, "Protected bills", "(Committed upcoming bills)", "-\$${protectedBills.toStringAsFixed(0)}", isNegative: true),
                          const Divider(height: 20),
                          _buildBreakdownRow(Icons.account_balance, "Usable cash buffer", "(\$2,000 − \$1,200)", "\$${usableBuffer.toStringAsFixed(0)}", isBold: true),
                          const Divider(height: 20),
                          _buildBreakdownRow(Icons.umbrella, "Hypothetical scenario cost", "(e.g., housing, repairs)", "\$${emergencyCost.toStringAsFixed(0)}"),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Potential Gap Alert ($2,000 - $1,200 - $1,000 = $200 gap)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.riskRedBg,
                      borderRadius: BorderRadius.circular(14),
                      border: const Border(left: BorderSide(color: AppTheme.riskRed, width: 4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppTheme.riskRed, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Potential Gap Detected", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.riskRedText)),
                              Text(
                                "\$${gap.toStringAsFixed(0)}",
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.riskRed),
                              ),
                              const Text(
                                "\$800 usable buffer cannot cover \$1,000 expense without touching committed bill money.",
                                style: TextStyle(fontSize: 10.5, color: AppTheme.riskRedText),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text("RECOMMENDED ACTIONS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.5)),
                  const SizedBox(height: 8),

                  _buildOptionTile(Icons.savings_outlined, "Move money from secondary savings buffer"),
                  const SizedBox(height: 6),
                  _buildOptionTile(Icons.credit_card_off_outlined, "Pause non-essential subscriptions"),
                  const SizedBox(height: 6),
                  _buildOptionTile(Icons.verified_user_outlined, "Explore an authorized short-term buffer"),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => context.go('/emergency/results'),
                      child: const Text("Adjust Scenario Amount or Buffer"),
                    ),
                  ),
                  const SizedBox(height: 12),

                  const DisclaimerBanner(
                    text: "Demo Scenarios: Emergency costs and gap estimates are user-modeled simulations. No insurance or reimbursement is guaranteed.",
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreakdownRow(IconData icon, String title, String subtitle, String amount, {bool isNegative = false, bool isBold = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.brandNavy),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12.5, fontWeight: isBold ? FontWeight.w800 : FontWeight.w700, color: AppTheme.brandNavy)),
              Text(subtitle, style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
            ],
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w800,
            color: isNegative ? AppTheme.riskRed : AppTheme.brandNavy,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionTile(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.brandNavy),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.brandNavy))),
          const Icon(Icons.chevron_right, size: 16, color: AppTheme.textMuted),
        ],
      ),
    );
  }
}
