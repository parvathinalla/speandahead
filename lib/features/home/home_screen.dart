import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_service.dart';
import '../../shared/status_badge.dart';

class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigateTab;
  const HomeScreen({super.key, this.onNavigateTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!AppState.instance.isLoaded) {
        AppState.instance.loadAllData();
      }
    });
  }

  void _goToTab(int tabIndex, String path) {
    if (widget.onNavigateTab != null) {
      widget.onNavigateTab!(tabIndex);
    } else {
      context.go(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppState.instance, AuthService.instance]),
      builder: (context, _) {
        final state = AppState.instance;
        final user = AuthService.instance.currentUser;

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => state.loadAllData(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with user profile and provider status badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: AppTheme.brandBlue,
                              child: Text(
                                user?.initials ?? "AS",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.name ?? "Alex Smith",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.brandNavy,
                                    fontFamily: 'Plus Jakarta Sans',
                                  ),
                                ),
                                Text(
                                  "Partner: ${user?.partnerName ?? "Sarah Smith"}",
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                        StatusBadge(type: state.dataSource, compact: true),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Accounts Overview Cards Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildAccountPill(
                            title: "Checking",
                            amount: "\$${state.checkingBalance.toStringAsFixed(0)}",
                            sub: "Primary •••• 7890",
                            color: AppTheme.brandNavy,
                            icon: Icons.account_balance_wallet_outlined,
                            onTap: () => _goToTab(1, '/bills'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAccountPill(
                            title: "Savings",
                            amount: "\$${state.savingsBalance.toStringAsFixed(0)}",
                            sub: "Emergency •••• 1122",
                            color: AppTheme.brandBlue,
                            icon: Icons.savings_outlined,
                            onTap: () => _goToTab(1, '/bills/transfer/review'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAccountPill(
                            title: "Joint",
                            amount: "\$${state.jointBalance.toStringAsFixed(0)}",
                            sub: "Joint •••• 4321",
                            color: const Color(0xFF0F766E),
                            icon: Icons.people_outline,
                            onTap: () => _goToTab(3, '/joint'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Bill Risk Warning Tile (-$170 Shortfall)
                    if (state.isShortfall)
                      Card(
                        color: AppTheme.riskRedBg,
                        child: InkWell(
                          onTap: () => _goToTab(1, '/bills/transfer/review'),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: const BoxDecoration(
                              borderRadius: BorderRadius.all(Radius.circular(16)),
                              border: Border(left: BorderSide(color: AppTheme.riskRed, width: 4.5)),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: AppTheme.riskRed, size: 22),
                                        SizedBox(width: 6),
                                        Text(
                                          "Bill Shortfall Warning",
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.riskRedText,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        "Short by \$${state.shortfallAmount.toStringAsFixed(0)}",
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.riskRed,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Checking balance (\$${state.checkingBalance.toStringAsFixed(0)}) is lower than upcoming 14-day bills (\$${state.billsDueTotal.toStringAsFixed(0)}). Avoid overdraft fees.",
                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.riskRedText, height: 1.35),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      "Review \$170 Safe Transfer",
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.riskRedText,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.arrow_forward_rounded, size: 14, color: AppTheme.riskRedText),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Card(
                        color: AppTheme.successGreenBg,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline, color: AppTheme.successGreenText),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Bills fully covered! Checking: \$${state.checkingBalance.toStringAsFixed(0)} vs bills \$${state.billsDueTotal.toStringAsFixed(0)}.",
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.successGreenText),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),

                    const Text(
                      "FEATURE SNAPSHOTS",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),

                    // Tile 1: Smart Card Suggestion
                    _buildFeatureCard(
                      icon: Icons.credit_card_rounded,
                      title: "Smart Card Recommendation",
                      subtitle: "For upcoming \$120 Whole Foods purchase",
                      badge: const StatusBadge(type: StatusBadgeType.simulation, compact: true),
                      body: "Card B (Savor One) gives 2% cashback and keeps utilization healthy (37% vs 87% on Venture).",
                      actionLabel: "Compare Cards",
                      onTap: () => _goToTab(2, '/cards'),
                    ),
                    const SizedBox(height: 10),

                    // Tile 2: Smart Utilization AutoPay Status
                    _buildFeatureCard(
                      icon: Icons.insights_rounded,
                      title: "Smart Utilization AutoPay",
                      subtitle: "Card balance \$750 • Target: 29%",
                      badge: const StatusBadge(type: StatusBadgeType.simulation, compact: true),
                      body:
                          "Full \$460 paydown is not safe today. Safe payment is \$250 (leaving \$500 balance / 50% util).",
                      actionLabel: "Configure AutoPay",
                      onTap: () => _goToTab(2, '/cards/autopay'),
                    ),
                    const SizedBox(height: 10),

                    // Tile 3: Joint Review Outlier
                    if (state.hasPendingJointReview)
                      _buildFeatureCard(
                        icon: Icons.people_outline_rounded,
                        title: "Joint Account Payment Review",
                        subtitle: "Unusual \$850 at Best Buy",
                        badge: const StatusBadge(type: StatusBadgeType.pendingReview, compact: true),
                        body:
                            "Requires partner confirmation for in-app initiated execution. (Sarah Smith)",
                        actionLabel: "Review Payment",
                        onTap: () => _goToTab(3, '/joint'),
                      ),
                    if (state.hasPendingJointReview) const SizedBox(height: 10),

                    // Tile 4: Emergency Readiness Snapshot
                    _buildFeatureCard(
                      icon: Icons.shield_outlined,
                      title: "Emergency Readiness",
                      subtitle: "\$1,000 Emergency Scenario",
                      badge: const StatusBadge(type: StatusBadgeType.demoFixture, compact: true),
                      body:
                          "Funds \$2,000 − Protected Bills \$1,200 − Emergency \$1,000 = \$200 Potential Gap.",
                      actionLabel: "Explore Buffer Options",
                      onTap: () => _goToTab(4, '/emergency'),
                    ),
                    const SizedBox(height: 14),

                    // Quick settings link
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.settings_outlined, size: 16),
                        label: const Text("App Preferences & Reserve Settings", style: TextStyle(fontSize: 12)),
                        onPressed: () => context.go('/settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountPill({
    required String title,
    required String amount,
    required String sub,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                amount,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget badge,
    required String body,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.brandBlueLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, size: 16, color: AppTheme.brandBlue),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.brandNavy,
                        ),
                      ),
                    ],
                  ),
                  badge,
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.brandBlue),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    actionLabel,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.brandBlue),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppTheme.brandBlue),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
