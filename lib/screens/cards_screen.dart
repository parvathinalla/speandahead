import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CardsScreen extends StatefulWidget {
  final Function(int)? onNavigateTab;
  const CardsScreen({super.key, this.onNavigateTab});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  int selectedCard = 1; // Savor One is recommended (Index 1)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                          "Best Card for This Purchase",
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.brandNavy),
                        ),
                        Text(
                          "Get the most rewards while keeping utilization healthy.",
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Purchase Simulator
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_cart, color: AppTheme.brandNavy, size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Groceries at Whole Foods", style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                            Text("\$120", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.brandNavy)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.brandBlueLight, borderRadius: BorderRadius.circular(12)),
                        child: const Text("Edit", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.brandBlue)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              const Text("Card Options", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),

              // Card 1: Venture Rewards (High utilization)
              _buildCardOption(
                index: 0,
                name: "Venture Rewards •••• 1234",
                themeNavy: true,
                rewardRate: "3%",
                utilization: "78%",
                statusLabel: "High utilization",
                isRed: true,
              ),
              const SizedBox(height: 10),

              // Card 2: Savor One (Healthy range)
              _buildCardOption(
                index: 1,
                name: "Savor One •••• 5678",
                themeNavy: false,
                rewardRate: "2%",
                utilization: "25%",
                statusLabel: "Healthy range",
                isRed: false,
              ),
              const SizedBox(height: 14),

              // AI Recommendation Card
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
                    Icon(Icons.lightbulb, color: AppTheme.brandBlue, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Recommended", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.brandBlue)),
                          SizedBox(height: 2),
                          Text("Choose Card B (Savor One)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                          SizedBox(height: 4),
                          Text(
                            "You'll still earn 2% rewards and keep your utilization low, which can help your overall credit health over time.",
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Selected Savor One for \$120 Whole Foods grocery purchase!")),
                    );
                  },
                  child: const Text("Choose Card B"),
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    // Navigate to AutoPay screen
                    if (widget.onNavigateTab != null) {
                      widget.onNavigateTab!(2); // Tab index 2 is AutoPay
                    }
                  },
                  child: const Text("Pay down \$200 first"),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  "This is a suggestion only. We do not guarantee any change to your credit score.",
                  style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardOption({
    required int index,
    required String name,
    required bool themeNavy,
    required String rewardRate,
    required String utilization,
    required String statusLabel,
    required bool isRed,
  }) {
    final isSelected = selectedCard == index;
    return GestureDetector(
      onTap: () => setState(() => selectedCard = index),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
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
                      : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: themeNavy ? null : Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: themeNavy ? Colors.white : AppTheme.brandNavy)),
                      Text("VISA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: themeNavy ? Colors.white : AppTheme.brandNavy)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.card_giftcard, size: 16, color: AppTheme.brandNavy),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(rewardRate, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                                const Text("Rewards on groceries", style: TextStyle(fontSize: 9, color: AppTheme.textMuted)),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(utilization, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isRed ? AppTheme.riskRed : AppTheme.successGreen)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isRed ? AppTheme.riskRedBg : AppTheme.successGreenBg,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: isRed ? AppTheme.riskRedText : AppTheme.successGreenText),
                                  ),
                                ),
                              ],
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
