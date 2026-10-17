import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/status_badge.dart';

class BillsScreen extends StatelessWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final checking = state.checkingBalance;
        final billsDue = state.billsDueTotal;
        final shortfall = state.shortfallAmount;

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
                                fontFamily: 'Plus Jakarta Sans',
                              ),
                            ),
                            Text(
                              "See if your upcoming bills will be covered and take action early.",
                              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      StatusBadge(type: state.dataSource, compact: true),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Two Cards Row: Checking Balance & Bills Due (14d)
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
                                Text(
                                  "\$${checking.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.brandNavy,
                                    fontFamily: 'Plus Jakarta Sans',
                                  ),
                                ),
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
                                Text(
                                  "\$${billsDue.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.brandNavy,
                                    fontFamily: 'Plus Jakarta Sans',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Red Shortfall Alert Banner ($170 demo warning)
                  if (state.isShortfall)
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
                                const Text("You may be short by", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.riskRedText)),
                                Text(
                                  "\$${shortfall.toStringAsFixed(0)}",
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.riskRed),
                                ),
                                const Text(
                                  "First shortfall hits on Oct 20 (Rent). Action needed.",
                                  style: TextStyle(fontSize: 10.5, color: AppTheme.riskRedText),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.successGreenBg,
                        borderRadius: BorderRadius.circular(14),
                        border: const Border(left: BorderSide(color: AppTheme.successGreen, width: 4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: AppTheme.successGreen, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("All Bills Covered", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.successGreenText)),
                                Text("Safe savings transfer has resolved projected overdraft risk.", style: TextStyle(fontSize: 11, color: AppTheme.successGreenText)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Projected Balance Panel (14 Days)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Projected Balance (Next 14 Days)",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.brandNavy),
                              ),
                              InkWell(
                                onTap: () => context.go('/bills/forecast'),
                                child: const Row(
                                  children: [
                                    Text("Calendar", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.brandBlue)),
                                    Icon(Icons.chevron_right, size: 14, color: AppTheme.brandBlue),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            height: 90,
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: CustomPaint(
                              painter: BalanceChartPainter(isResolved: !state.isShortfall),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Oct 17 (\$450)", style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              Text("Oct 20 (-Rent)", style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              Text("Oct 31 (-\$170)", style: TextStyle(fontSize: 10, color: AppTheme.riskRedText, fontWeight: FontWeight.w700)),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Upcoming Bills (4)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
                              InkWell(
                                onTap: () => context.go('/bills/forecast'),
                                child: const Text("See all", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.brandBlue)),
                              ),
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

                  // CTA Button to Transfer Review Screen
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => context.go('/bills/transfer/review'),
                      child: Text(state.isShortfall ? "Review savings options (\$170)" : "View transfer history"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
  final bool isResolved;
  const BalanceChartPainter({this.isResolved = false});

  @override
  void paint(Canvas canvas, Size size) {
    final zeroLineY = size.height * 0.65;
    final dashPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, zeroLineY), Offset(size.width, zeroLineY), dashPaint);

    // Blue line for available positive balance
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

    if (isResolved) {
      // Line remains positive after transfer
      final greenPaint = Paint()
        ..color = AppTheme.successGreen
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke;
      final greenPath = Path()
        ..moveTo(size.width * 0.65, size.height * 0.52)
        ..lineTo(size.width * 0.85, size.height * 0.40)
        ..lineTo(size.width * 0.95, size.height * 0.32);
      canvas.drawPath(greenPath, greenPaint);
      canvas.drawCircle(Offset(size.width * 0.95, size.height * 0.32), 4, Paint()..color = AppTheme.successGreen);
    } else {
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
      canvas.drawCircle(Offset(size.width * 0.95, size.height * 0.9), 4, Paint()..color = AppTheme.riskRed);
    }
  }

  @override
  bool shouldRepaint(covariant BalanceChartPainter oldDelegate) => oldDelegate.isResolved != isResolved;
}
