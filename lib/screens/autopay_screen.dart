import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class AutoPayScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const AutoPayScreen({super.key, this.onBack});

  @override
  State<AutoPayScreen> createState() => _AutoPayScreenState();
}

class _AutoPayScreenState extends State<AutoPayScreen> {
  double targetUtil = 29.0;
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  Future<void> _fetchPreview() async {
    final res = await ApiService.getAutoPayPreview(targetPct: targetUtil);
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

    final limit = data?["card_limit"] ?? 1000;
    final balance = data?["current_balance"] ?? 750;
    final util = data?["current_utilization_pct"] ?? 75;
    final suggested = data?["suggested_paydown_amount"] ?? 460;
    final checking = data?["checking_funds"] ?? 600;
    final bills = data?["upcoming_bills_2weeks"] ?? 250;
    final buffer = data?["safety_buffer"] ?? 100;
    final safeCap = data?["max_safe_payment_today"] ?? 250;
    final isAffordable = data?["is_full_payment_affordable"] ?? false;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Banner with Dark Navy Gradient (Image 8)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF07284C), Color(0xFF0A3D75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.onBack != null)
                          GestureDetector(
                            onTap: widget.onBack,
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chevron_left, color: Colors.white, size: 20),
                            ),
                          ),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Smart Utilization AutoPay",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                              Text(
                                "Plan an early card payment",
                                style: TextStyle(fontSize: 11, color: Color(0xFF93C5FD)),
                              ),
                            ],
                          ),
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
                              Icon(Icons.calendar_today, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text("Pay Early\nKeep < 30%", style: TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Make a payment before your balance is reported to help keep your credit utilization under control.",
                      style: TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1), height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Card Status Panel
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.credit_card, size: 16, color: AppTheme.brandNavy),
                              SizedBox(width: 6),
                              Text("Venture Rewards Card", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                              SizedBox(width: 4),
                              Text("•••• 1234", style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                            ],
                          ),
                          Text("View Details ›", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.brandBlue)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMetricCol("Credit limit", "\$$limit", false),
                          _buildMetricCol("Balance", "\$$balance", false),
                          _buildMetricCol("Current utilization", "$util%", true),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                          value: 0.75,
                          minHeight: 8,
                          backgroundColor: Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.riskRed),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("0%", style: TextStyle(fontSize: 9, color: AppTheme.textMuted)),
                          Text("100%", style: TextStyle(fontSize: 9, color: AppTheme.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Target Selector
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.track_changes, color: AppTheme.brandNavy, size: 20),
                          SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Set your target utilization ⓘ", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                              Text("We recommend keeping it below 30%.", style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
                            ],
                          ),
                        ],
                      ),
                      DropdownButton<double>(
                        value: targetUtil,
                        underline: const SizedBox(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.brandNavy),
                        items: const [
                          DropdownMenuItem(value: 29.0, child: Text("29%")),
                          DropdownMenuItem(value: 25.0, child: Text("25%")),
                          DropdownMenuItem(value: 20.0, child: Text("20%")),
                          DropdownMenuItem(value: 15.0, child: Text("15%")),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => targetUtil = val);
                            _fetchPreview();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Suggested Paydown & New Utilization Cards
              Row(
                children: [
                  Expanded(
                    flex: 14,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.calculate_outlined, size: 14, color: AppTheme.textSecondary),
                                SizedBox(width: 4),
                                Text("Suggested payment ⓘ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text("\$$suggested", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.successGreenText)),
                            const SizedBox(height: 4),
                            const Text("Before estimated statement close: Oct 23 📅", style: TextStyle(fontSize: 8.5, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 10,
                    child: Card(
                      color: const Color(0xFFF0FDF4),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.trending_down, size: 14, color: Color(0xFF047857)),
                                SizedBox(width: 4),
                                Expanded(child: Text("New utilization (after payment)", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF047857)))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text("${targetUtil.toInt()}%", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF047857))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Affordability Safety Check Box
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.monetization_on_outlined, color: AppTheme.brandNavy, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Can you afford this payment?", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                                Text("We check your available funds and upcoming bills to keep you on track.", style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      _buildAffordRow("Checking funds", "\$$checking", false),
                      const SizedBox(height: 4),
                      _buildAffordRow("Upcoming bills (next 2 weeks)", "-\$$bills", true),
                      const SizedBox(height: 4),
                      _buildAffordRow("Safety buffer (for essentials)", "-\$$buffer", true),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Safe payment today", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                          Text("\$$safeCap", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.brandBlue)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Warning alert if full payment exceeds safe cash
              if (!isAffordable)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.riskRedBg,
                    borderRadius: BorderRadius.circular(12),
                    border: const Border(left: BorderSide(color: AppTheme.riskRed, width: 4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.riskRed, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Full \$$suggested payment is not affordable today.",
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.riskRedText),
                            ),
                            const Text(
                              "Choose a smaller payment or change the target.",
                              style: TextStyle(fontSize: 10, color: AppTheme.riskRedText),
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
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Authorize Safe Paydown"),
                        content: Text(
                          "Schedule a simulated paydown of \$$safeCap before the Oct 23 statement close date?\n\nThis keeps your \$100 essential reserve and upcoming bills covered.",
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("✓ Safe paydown of \$$safeCap scheduled into ledger!")),
                              );
                            },
                            child: const Text("Authorize Schedule"),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text("Review safe payment →"),
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text("Change target"),
                ),
              ),
              const SizedBox(height: 10),

              const Center(
                child: Text(
                  "ⓘ Credit score changes are not guaranteed. Lower utilization may help, but results vary. Sandbox simulation.",
                  style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCol(String label, String val, bool isRed) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isRed ? AppTheme.riskRed : AppTheme.brandNavy),
        ),
      ],
    );
  }

  Widget _buildAffordRow(String label, String val, bool isRed) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        Text(
          val,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isRed ? AppTheme.riskRed : AppTheme.brandNavy),
        ),
      ],
    );
  }
}
