import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class AutoPayScreen extends StatelessWidget {
  const AutoPayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        // const limit = 1000.0;
        // const balance = 750.0;
        // const checking = 600.0;
        // const bills = 250.0;
        // const reserve = 100.0;
        // final targetUtil = state.targetUtilizationPct;
        // final theoreticalPaydown = state.theoreticalPaydown; // $460
        // final safePayment = state.maxSafePaymentToday; // $250
        // final targetReachable = state.targetReachable; // false

        return Scaffold(
          appBar: AppBar(
            title: const Text("Smart Utilization AutoPay"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/cards'),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.list_alt_rounded),
                tooltip: "Active Plans",
                onPressed: () => context.go('/cards/autopay/plans'),
              ),
              const Padding(
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
                  // Top Hero Card (Navy Gradient)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF07284C), Color(0xFF0A3D75)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Venture Rewards •••• 1234",
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text("Est. Close: Oct 23", style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Make an early payment before your statement is reported to keep your revolving utilization under control.",
                          style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), height: 1.35),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildHeroStat("Card Balance", "\$750"),
                            _buildHeroStat("Credit Limit", "\$1,000"),
                            _buildHeroStat("Current Util.", "75% (High)", isRisk: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Target Utilization Selector Slider
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("TARGET UTILIZATION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.brandBlueLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "${targetUtil.toStringAsFixed(0)}%",
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.brandBlue),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: targetUtil,
                            min: 10.0,
                            max: 50.0,
                            divisions: 8,
                            activeColor: AppTheme.brandBlue,
                            inactiveColor: const Color(0xFFE2E8F0),
                            label: "${targetUtil.toStringAsFixed(0)}%",
                            onChanged: (val) => state.updateAutoPayTarget(val),
                          ),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("10% (Ultra-low)", style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              Text("29% (Recommended <30%)", style: TextStyle(fontSize: 10, color: AppTheme.brandBlue, fontWeight: FontWeight.w700)),
                              Text("50%", style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Required Calculation Warning Banner: Target Not Reachable Safely Today
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.riskRedBg,
                      borderRadius: BorderRadius.circular(14),
                      border: const Border(left: BorderSide(color: AppTheme.riskRed, width: 4.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: AppTheme.riskRed, size: 22),
                            SizedBox(width: 8),
                            Text(
                              "Target 29% Is Not Reachable Safely Today",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.riskRedText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Theoretical paydown needed for 29% is \$460. However, your available checking funds only permit a maximum safe payment of \$250 today.",
                          style: TextStyle(fontSize: 11.5, color: AppTheme.riskRedText, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Math & Constraints Breakdown Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("SAFETY CONSTRAINT BREAKDOWN", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                          const Divider(height: 16),
                          _buildMathRow("Available Checking Funds", "+\$600.00", isPositive: true),
                          _buildMathRow("Protected Bills (Next 14d)", "-\$250.00", isNegative: true),
                          _buildMathRow("Minimum Checking Reserve", "-\$100.00", isNegative: true),
                          const Divider(height: 16),
                          _buildMathRow("Maximum Safe Payment Allowed", "\$250.00", isBold: true, color: AppTheme.brandBlue),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Resulting Modeled Utilization:",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.brandNavy),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Current \$750 − Safe \$250 = \$500 balance → 50% utilization (down from 75%).",
                                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => context.go('/cards/autopay/review'),
                      child: const Text("Review Safe \$250 AutoPay Plan"),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/cards/autopay/plans'),
                      child: const Text("View Existing Scheduled Plans", style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  const DisclaimerBanner(
                    text: "Statement Close Date: Oct 23 is a simulated estimate. CreditPilot does not guarantee credit bureau reporting dates or exact bureau score formulas.",
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroStat(String title, String val, {bool isRisk = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: isRisk ? const Color(0xFFFCA5A5) : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildMathRow(String label, String amount, {bool isPositive = false, bool isNegative = false, bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: isBold ? FontWeight.w800 : FontWeight.w500, color: AppTheme.textSecondary)),
          Text(
            amount,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: color ?? (isPositive ? AppTheme.successGreen : (isNegative ? AppTheme.riskRed : AppTheme.brandNavy)),
            ),
          ),
        ],
      ),
    );
  }
}
