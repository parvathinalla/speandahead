import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class CardCompareScreen extends StatelessWidget {
  const CardCompareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Card Comparison"),
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
              const Text(
                "COMPARE MODELED CARDS",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.5),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(1.0),
                      2: FlexColumnWidth(1.0),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(color: AppTheme.borderSubtle, width: 1),
                    ),
                    children: [
                      _buildHeaderRow(),
                      _buildTableRow("Credit Limit", "\$1,000", "\$1,000"),
                      _buildTableRow("Current Balance", "\$750", "\$250"),
                      _buildTableRow("Current Util.", "75% (High)", "25% (Healthy)", isColorAlert: true),
                      _buildTableRow("Grocery Cashback", "3.0%", "2.0%"),
                      _buildTableRow("Dining Cashback", "2.0%", "3.0%"),
                      _buildTableRow("Est. Statement", "Oct 23 (Est.)", "Oct 28 (Est.)"),
                      _buildTableRow("Recommended Role", "Paydown first", "Everyday spend"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.brandBlueLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.insights_rounded, color: AppTheme.brandBlue, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Recommendation Insight: Savor One is the safer choice for active charging. Venture Rewards should be paid down below 30% first.",
                        style: TextStyle(fontSize: 11.5, color: AppTheme.brandNavy, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => context.go('/cards/autopay'),
                  child: const Text("Plan Venture Rewards AutoPay"),
                ),
              ),
              const SizedBox(height: 14),

              const DisclaimerBanner(
                text: "Simulated comparison data. Cards, limits, statement dates, and reward categories are demo models.",
              ),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _buildHeaderRow() {
    return const TableRow(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text("Metric", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text("Venture", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text("Savor One", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.brandBlue)),
        ),
      ],
    );
  }

  TableRow _buildTableRow(String metric, String val1, String val2, {bool isColorAlert = false}) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(metric, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            val1,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isColorAlert ? AppTheme.riskRed : AppTheme.brandNavy,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            val2,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isColorAlert ? AppTheme.successGreen : AppTheme.brandNavy,
            ),
          ),
        ),
      ],
    );
  }
}
