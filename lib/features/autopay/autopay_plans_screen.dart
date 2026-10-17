import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../core/error_states/error_boundary.dart';
import '../../shared/status_badge.dart';

class AutoPayPlansScreen extends StatelessWidget {
  const AutoPayPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final plans = state.autopayPlans;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Active AutoPay Plans"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/cards/autopay'),
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 12),
                child: StatusBadge(type: StatusBadgeType.simulation, compact: true),
              ),
            ],
          ),
          body: SafeArea(
            child: plans.isEmpty
                ? EmptyStateView(
                    icon: Icons.insights_rounded,
                    title: "No Active AutoPay Plans",
                    message: "You haven't scheduled any early card paydown plans yet.",
                    buttonText: "Create a Plan",
                    onAction: () => context.go('/cards/autopay'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: plans.length,
                    itemBuilder: (context, index) {
                      final plan = plans[index];
                      final planId = plan["plan_id"] as String;
                      final cardName = plan["card_name"] as String? ?? "Venture Rewards";
                      final amount = plan["payment_amount"] as num? ?? 250.0;
                      final target = plan["target_utilization_pct"] as num? ?? 29.0;
                      final date = plan["scheduled_date"] as String? ?? "Oct 22, 2026";
                      final status = plan["status"] as String? ?? "scheduled";

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    cardName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.brandNavy,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.successGreenBg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.successGreenText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Payment: \$${amount.toStringAsFixed(2)}",
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.brandBlue),
                                      ),
                                      Text(
                                        "Target: ${target.toStringAsFixed(0)}% util",
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        "Execution Date",
                                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                      ),
                                      Text(
                                        date,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.brandNavy),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.cancel_outlined, size: 16, color: AppTheme.riskRed),
                                    label: const Text("Cancel Plan", style: TextStyle(color: AppTheme.riskRed, fontSize: 12)),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text("Cancel AutoPay Plan?"),
                                          content: Text("Are you sure you want to cancel the scheduled \$${amount.toStringAsFixed(2)} payment on $date?"),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Keep Plan")),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.riskRed),
                                              onPressed: () {
                                                state.cancelAutoPayPlan(planId);
                                                Navigator.pop(ctx);
                                              },
                                              child: const Text("Yes, Cancel"),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}
