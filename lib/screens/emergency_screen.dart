import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

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
                    child: const Icon(Icons.shield_outlined, color: AppTheme.brandBlue),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Emergency Readiness",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.brandNavy),
                        ),
                        Text(
                          "See if your current funds can cover an unexpected emergency.",
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Hero Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
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
                              "Based on your current accounts and a typical emergency scenario.",
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

              // Funds & Bills Breakdown
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _buildBreakdownRow(Icons.account_balance_wallet, "Available funds", "(Checking + Savings)", "\$2,000"),
                      const Divider(height: 20),
                      _buildBreakdownRow(Icons.description, "Protected bills", "(Already committed)", "\$1,200"),
                      const Divider(height: 20),
                      _buildBreakdownRow(Icons.umbrella, "Estimated emergency cost", "(e.g., housing, food, transport)", "\$1,000"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Potential Gap Alert
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.riskRedBg,
                  borderRadius: BorderRadius.circular(14),
                  border: const Border(left: BorderSide(color: AppTheme.riskRed, width: 4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.riskRed, size: 28),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Potential gap", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.riskRedText)),
                        Text("\$200", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.riskRed)),
                        Text("Your current funds may not fully cover an emergency.", style: TextStyle(fontSize: 10.5, color: AppTheme.riskRedText)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              const Text("Here are some options:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),

              _buildOptionTile(Icons.savings_outlined, "Move money from savings"),
              const SizedBox(height: 6),
              _buildOptionTile(Icons.credit_card_off_outlined, "Pause non-essential spending"),
              const SizedBox(height: 6),
              _buildOptionTile(Icons.verified_user_outlined, "Explore a small emergency buffer"),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text("Explore options"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(IconData icon, String title, String sub, String val) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.brandNavy),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
              Text(sub, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
            ],
          ),
        ),
        Text(val, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
      ],
    );
  }

  Widget _buildOptionTile(IconData icon, String title) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppTheme.brandNavy),
        title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        dense: true,
        onTap: () {},
      ),
    );
  }
}
