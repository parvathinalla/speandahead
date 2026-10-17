import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class CardMerchantScreen extends StatefulWidget {
  const CardMerchantScreen({super.key});

  @override
  State<CardMerchantScreen> createState() => _CardMerchantScreenState();
}

class _CardMerchantScreenState extends State<CardMerchantScreen> {
  int _selectedCardIndex = 1; // Card B (Savor One) is recommended

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Purchase Evaluation"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/cards'),
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
              // Purchase Simulator Header
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_cart_rounded, color: AppTheme.brandNavy, size: 26),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Groceries at Whole Foods", style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                            Text("\$120.00", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.brandNavy)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppTheme.brandBlueLight, borderRadius: BorderRadius.circular(10)),
                        child: const Text("Category: Groceries", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.brandBlue)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              const Text("CARD OPTIONS EVALUATED", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 8),

              // Card 1: Venture Rewards (High utilization trade-off)
              _buildCardOptionTile(
                index: 0,
                name: "Venture Rewards •••• 1234",
                themeNavy: true,
                rewardRatePct: "3%",
                rewardDollars: "\$3.60",
                utilizationBefore: "75%",
                utilizationAfter: "87%",
                statusLabel: "High utilization (87%)",
                isRed: true,
              ),
              const SizedBox(height: 10),

              // Card 2: Savor One (Healthy range - Recommended)
              _buildCardOptionTile(
                index: 1,
                name: "Savor One •••• 5678",
                themeNavy: false,
                rewardRatePct: "2%",
                rewardDollars: "\$2.40",
                utilizationBefore: "25%",
                utilizationAfter: "37%",
                statusLabel: "Healthy range (37%)",
                isRed: false,
              ),
              const SizedBox(height: 14),

              // AI Recommendation Card with trade-off breakdown ($3.60 vs $2.40)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.brandBlueLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_rounded, color: AppTheme.brandBlue, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("RECOMMENDED: CHOOSE CARD B", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.brandBlue)),
                          SizedBox(height: 3),
                          Text("Choose Savor One •••• 5678", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                          SizedBox(height: 4),
                          Text(
                            "Trade-off: Card A gives \$1.20 more in rewards (\$3.60 vs \$2.40), but pushes utilization to 87%. Card B keeps utilization in the healthy 37% range, supporting your overall credit profile.",
                            style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action buttons
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_selectedCardIndex == 1
                            ? "Selected Card B (Savor One) for \$120 Whole Foods grocery run."
                            : "Selected Card A (Venture Rewards). Caution: 87% utilization."),
                      ),
                    );
                    context.go('/cards');
                  },
                  child: Text(_selectedCardIndex == 1 ? "Choose Card B (Recommended)" : "Choose Card A"),
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => context.go('/cards/autopay'),
                  child: const Text("Pay down \$200 first with AutoPay"),
                ),
              ),
              const SizedBox(height: 14),

              const DisclaimerBanner(
                text: "Suggestion only. We do not guarantee any change to your credit score or official credit bureau reports.",
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardOptionTile({
    required int index,
    required String name,
    required bool themeNavy,
    required String rewardRatePct,
    required String rewardDollars,
    required String utilizationBefore,
    required String utilizationAfter,
    required String statusLabel,
    required bool isRed,
  }) {
    final isSelected = _selectedCardIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedCardIndex = index),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppTheme.brandBlue : AppTheme.borderSubtle,
                width: 2,
              ),
            ),
            child: isSelected
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.brandBlue,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: themeNavy
                      ? [const Color(0xFF07284C), const Color(0xFF13467D)]
                      : [const Color(0xFFF8FAFC), const Color(0xFFEEF2F6)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: themeNavy ? null : Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: themeNavy ? Colors.white : AppTheme.brandNavy)),
                      Text("VISA", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: themeNavy ? Colors.white70 : AppTheme.brandNavy)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Rewards in Dollars and Percentage
                        Row(
                          children: [
                            const Icon(Icons.card_giftcard, size: 16, color: AppTheme.brandNavy),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "$rewardDollars ($rewardRatePct)",
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy),
                                ),
                                const Text("Rewards earned", style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
                              ],
                            ),
                          ],
                        ),
                        // Post-purchase utilization
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "$utilizationBefore → $utilizationAfter",
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isRed ? AppTheme.riskRed : AppTheme.successGreen),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isRed ? AppTheme.riskRedBg : AppTheme.successGreenBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: isRed ? AppTheme.riskRedText : AppTheme.successGreenText),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
