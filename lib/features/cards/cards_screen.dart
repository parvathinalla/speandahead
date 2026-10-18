import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class CardsScreen extends StatelessWidget {
  final Function(int)? onNavigateTab;
  const CardsScreen({super.key, this.onNavigateTab});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        //final state = AppState.instance;

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
                        child: const Icon(Icons.credit_card, color: AppTheme.brandBlue),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Cards & Smart AutoPay",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.brandNavy,
                                fontFamily: 'Plus Jakarta Sans',
                              ),
                            ),
                            Text(
                              "Model rewards, utilization impact, and early paydowns.",
                              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const StatusBadge(type: StatusBadgeType.simulation, compact: true),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Flagship Smart AutoPay Entry Banner (Lives INSIDE Cards!)
                  Card(
                    color: AppTheme.brandNavy,
                    child: InkWell(
                      onTap: () => context.go('/cards/autopay'),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF07284C), Color(0xFF0C4A8E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.insights_rounded, color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      "Smart Utilization AutoPay",
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: const Text("Keep < 30%", style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Card Balance \$750 / \$1,000 (75% util). Modeled target 29% needs \$460 paydown. Checking safe limit is \$250.",
                              style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), height: 1.35),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  "Configure AutoPay Plan",
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF93C5FD)),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF93C5FD)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Purchase Simulator Quick Launch Tile ($120 Whole Foods Groceries)
                  Card(
                    child: InkWell(
                      onTap: () => context.go('/cards/merchant'),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppTheme.brandBlueLight, borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.shopping_cart_outlined, color: AppTheme.brandBlue, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Simulate Purchase Decision", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                                  Text("Groceries at Whole Foods • \$120", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: AppTheme.brandBlueLight, borderRadius: BorderRadius.circular(10)),
                              child: const Text("Simulate", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.brandBlue)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "MODELED CARDS INVENTORY (2)",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.5),
                      ),
                      InkWell(
                        onTap: () => context.go('/cards/compare'),
                        child: const Text("Side-by-Side Compare", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.brandBlue)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Card 1: Venture Rewards (High utilization)
                  _buildCardInventoryItem(
                    name: "Venture Rewards •••• 1234",
                    balance: "\$750.00",
                    limit: "\$1,000.00",
                    utilization: "75%",
                    rewards: "3% cashback on groceries",
                    isWarning: true,
                    expectedStatement: "Est. close: Oct 23",
                    isNavy: true,
                  ),
                  const SizedBox(height: 10),

                  // Card 2: Savor One (Healthy range)
                  _buildCardInventoryItem(
                    name: "Savor One •••• 5678",
                    balance: "\$250.00",
                    limit: "\$1,000.00",
                    utilization: "25%",
                    rewards: "2% cashback on groceries",
                    isWarning: false,
                    expectedStatement: "Est. close: Oct 28",
                    isNavy: false,
                  ),
                  const SizedBox(height: 16),

                  const DisclaimerBanner(
                    text: "Modeled Cards & Rewards: Values reflect simulated fixture profiles. We do not guarantee any change to your credit score.",
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardInventoryItem({
    required String name,
    required String balance,
    required String limit,
    required String utilization,
    required String rewards,
    required bool isWarning,
    required String expectedStatement,
    required bool isNavy,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isNavy
              ? [const Color(0xFF07284C), const Color(0xFF13467D)]
              : [const Color(0xFFF8FAFC), const Color(0xFFEEF2F6)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: isNavy ? null : Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isNavy ? Colors.white : AppTheme.brandNavy)),
              Text("VISA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: isNavy ? Colors.white70 : AppTheme.brandNavy)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Balance: $balance / $limit", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
                    const SizedBox(height: 2),
                    Text(rewards, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      utilization,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isWarning ? AppTheme.riskRed : AppTheme.successGreen,
                      ),
                    ),
                    Text(
                      isWarning ? "High utilization" : "Healthy range",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isWarning ? AppTheme.riskRedText : AppTheme.successGreenText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              expectedStatement,
              style: TextStyle(fontSize: 10, color: isNavy ? const Color(0xFF94A3B8) : AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
