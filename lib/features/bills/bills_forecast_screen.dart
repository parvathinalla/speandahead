import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/status_badge.dart';

class BillsForecastScreen extends StatelessWidget {
  const BillsForecastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        final calendarDays = [
          {"date": "Oct 17", "day": "Thu", "event": "Starting Balance", "impact": "+\$450", "balance": "\$450", "isRisk": false},
          {"date": "Oct 18", "day": "Fri", "event": "No scheduled bills", "impact": "--", "balance": "\$450", "isRisk": false},
          {"date": "Oct 19", "day": "Sat", "event": "Weekend buffer", "impact": "--", "balance": "\$450", "isRisk": false},
          {"date": "Oct 20", "day": "Sun", "event": "Rent (Installment)", "impact": "-\$360", "balance": "\$90", "isRisk": false},
          {"date": "Oct 21", "day": "Mon", "event": "Safe threshold", "impact": "--", "balance": "\$90", "isRisk": false},
          {"date": "Oct 22", "day": "Tue", "event": "Electricity Bill", "impact": "-\$120", "balance": "-\$30", "isRisk": true},
          {"date": "Oct 25", "day": "Fri", "event": "Internet Bill", "impact": "-\$60", "balance": "-\$90", "isRisk": true},
          {"date": "Oct 28", "day": "Mon", "event": "Phone Bill", "impact": "-\$80", "balance": "-\$170", "isRisk": true},
          {"date": "Oct 31", "day": "Thu", "event": "Forecast Horizon End", "impact": "--", "balance": "-\$170", "isRisk": true},
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text("14-Day Bills Calendar"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/bills'),
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 12),
                child: StatusBadge(type: StatusBadgeType.demoFixture, compact: true),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overview Box
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Starting Checking Balance", style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                              Text("\$${state.checkingBalance.toStringAsFixed(0)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Total Upcoming Bills (14d)", style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                              Text("-\$${state.billsDueTotal.toStringAsFixed(0)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.riskRed)),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Projected End Balance", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                              Text(
                                state.isShortfall ? "-\$${state.shortfallAmount.toStringAsFixed(0)}" : "\$0",
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: state.isShortfall ? AppTheme.riskRed : AppTheme.successGreen),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    "DAY-BY-DAY CASH OBLIGATION TIMELINE",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),

                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: calendarDays.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final item = calendarDays[i];
                        final isRisk = item["isRisk"] as bool && state.isShortfall;
                        return Container(
                          color: isRisk ? AppTheme.riskRedBg.withValues(alpha: 0.4) : null,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 55,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item["date"] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: isRisk ? AppTheme.riskRedText : AppTheme.brandNavy,
                                      ),
                                    ),
                                    Text(
                                      item["day"] as String,
                                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item["event"] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isRisk ? FontWeight.w700 : FontWeight.w500,
                                    color: isRisk ? AppTheme.riskRedText : AppTheme.brandNavy,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    item["impact"] as String,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isRisk ? AppTheme.riskRed : AppTheme.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    "Bal: ${state.isShortfall ? item["balance"] : "Safe"}",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isRisk ? FontWeight.w800 : FontWeight.w500,
                                      color: isRisk ? AppTheme.riskRed : AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => context.go('/bills/transfer/review'),
                      child: const Text("Review Safe Savings Transfer"),
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
}
