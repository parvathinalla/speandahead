import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class JointScreen extends StatelessWidget {
  const JointScreen({super.key});

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
                    child: const Icon(Icons.people, color: AppTheme.brandBlue),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Joint Account Check",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.brandNavy),
                        ),
                        Text(
                          "Get a heads up on unusual payments from your joint account.",
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Unusual Payment Detected Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.riskRedBg,
                  borderRadius: BorderRadius.circular(14),
                  border: const Border(left: BorderSide(color: AppTheme.riskRed, width: 4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline, color: AppTheme.riskRed, size: 28),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Unusual Payment Detected", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.riskRedText)),
                        Text("\$850", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.riskRed)),
                        Text("at Best Buy • Today, 10:24 AM", style: TextStyle(fontSize: 11, color: AppTheme.riskRedText)),
                      ],
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
                    Text("This amount is higher than usual for this account.", style: TextStyle(fontSize: 11, color: Color(0xFF0369A1), fontWeight: FontWeight.w600)),
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
                      _buildRow(Icons.credit_card, "Amount", "\$850"),
                      const Divider(height: 16),
                      _buildRow(Icons.access_time, "Date & Time", "Oct 17, 2026, 10:24 AM"),
                      const Divider(height: 16),
                      _buildRow(Icons.label_outline, "Category", "Electronics"),
                      const Divider(height: 16),
                      _buildRow(Icons.account_balance, "Account", "Joint Checking (•••• 4321)"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Partner notify prompt
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
                            Text("Notify your partner?", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                            Text("Send a quick alert so they can confirm this payment.", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
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
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✓ Confirmation request sent to Sarah Smith!")),
                    );
                  },
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text("Request confirmation"),
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text("Review details"),
                ),
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: AppTheme.textMuted),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "This works for in-app initiated payments. It does not block all transactions at the bank level.",
                        style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(IconData icon, String label, String val) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
      ],
    );
  }
}
