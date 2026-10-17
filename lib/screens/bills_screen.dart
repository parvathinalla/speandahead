import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final res = await ApiService.getBillForecast();
    if (mounted) {
      setState(() {
        data = res;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final checking = data?["checking_balance"] ?? 450;
    final billsDue = data?["total_bills_due"] ?? 620;
    final shortfall = data?["shortfall_amount"] ?? 170;

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
                    child: const Icon(Icons.calendar_month, color: AppTheme.brandBlue),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Bill Forecast",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.brandNavy,
                          ),
                        ),
                        Text(
                          "See if your upcoming bills will be covered and take action early.",
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Two Cards Row
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.credit_card, size: 14, color: AppTheme.textSecondary),
                                SizedBox(width: 4),
                                Text("Checking Balance", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text("\$$checking", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.receipt_long, size: 14, color: AppTheme.textSecondary),
                                SizedBox(width: 4),
                                Text("Bills Due (14d)", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text("\$$billsDue", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Red Shortfall Alert Banner
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("You may be short by", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.riskRedText)),
                        Text("\$$shortfall", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.riskRed)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Projected Balance Panel
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Projected Balance (Next 14 Days)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
                          Icon(Icons.info_outline, size: 14, color: AppTheme.textMuted),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        height: 90,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: CustomPaint(
                          painter: BalanceChartPainter(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Oct 17", style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                          Text("Oct 24", style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                          Text("Oct 31", style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Upcoming Bills List
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Upcoming Bills", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
                          Text("See all", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.brandBlue)),
                        ],
                      ),
                      const Divider(height: 20),
                      _buildBillItem(Icons.home, "Rent (Installment)", "Oct 20", "\$360"),
                      _buildBillItem(Icons.bolt, "Electricity", "Oct 22", "\$120"),
                      _buildBillItem(Icons.wifi, "Internet", "Oct 25", "\$60"),
                      _buildBillItem(Icons.phone_android, "Phone", "Oct 28", "\$80"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Savings Transfer Option"),
                        content: const Text(
                          "Transfer \$170.00 from Emergency Savings to Checking to avoid overdraft.\n\nRemaining savings balance: \$1,330.00.",
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Dismiss")),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Authorize Transfer")),
                        ],
                      ),
                    );
                  },
                  child: const Text("Review savings options"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillItem(IconData icon, String name, String date, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.brandNavy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
                Text(date, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Text(amount, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
        ],
      ),
    );
  }
}

class BalanceChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final zeroLineY = size.height * 0.65;
    final dashPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, zeroLineY), Offset(size.width, zeroLineY), dashPaint);

    // Blue Line above zero
    final bluePaint = Paint()
      ..color = AppTheme.brandBlue
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(10, size.height * 0.25)
      ..lineTo(size.width * 0.25, size.height * 0.38)
      ..lineTo(size.width * 0.45, size.height * 0.35)
      ..lineTo(size.width * 0.65, size.height * 0.52);

    canvas.drawPath(path, bluePaint);

    // Red dotted line dropping below zero to -$170
    final redPaint = Paint()
      ..color = AppTheme.riskRed
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final redPath = Path()
      ..moveTo(size.width * 0.65, size.height * 0.52)
      ..lineTo(size.width * 0.85, size.height * 0.75)
      ..lineTo(size.width * 0.95, size.height * 0.9);

    canvas.drawPath(redPath, redPaint);

    // End point circle
    canvas.drawCircle(Offset(size.width * 0.95, size.height * 0.9), 4, Paint()..color = AppTheme.riskRed);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
