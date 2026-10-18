import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/debounced_button.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class EmergencyResultsScreen extends StatefulWidget {
  const EmergencyResultsScreen({super.key});

  @override
  State<EmergencyResultsScreen> createState() => _EmergencyResultsScreenState();
}

class _EmergencyResultsScreenState extends State<EmergencyResultsScreen> {
  final TextEditingController _costController = TextEditingController(text: "1000");

  @override
  void dispose() {
    _costController.dispose();
    super.dispose();
  }

  Future<void> _recalculate() async {
    final cost = double.tryParse(_costController.text) ?? 1000.0;
    await AppState.instance.recalculateEmergency(cost);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Emergency Scenario Simulator"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/emergency'),
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("TEST AN EMERGENCY SCENARIO", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _costController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Estimated Emergency Cost",
                              prefixText: "\$ ",
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [500, 800, 1000, 1500].map((preset) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: Text("\$$preset", style: const TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    _costController.text = preset.toString();
                                    _recalculate();
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          DebouncedButton(
                            onPressed: _recalculate,
                            backgroundColor: AppTheme.brandBlue,
                            child: const Text("Recalculate Readiness Gap"),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Results Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: state.emergencyGap > 0 ? AppTheme.riskRedBg : AppTheme.successGreenBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: state.emergencyGap > 0 ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              state.emergencyGap > 0 ? "Readiness Gap" : "Fully Covered",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: state.emergencyGap > 0 ? AppTheme.riskRedText : AppTheme.successGreenText,
                              ),
                            ),
                            Text(
                              "\$${state.emergencyGap.toStringAsFixed(0)}",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: state.emergencyGap > 0 ? AppTheme.riskRed : AppTheme.successGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.emergencyGap > 0
                              ? "Liquid funds (\$2,000) minus protected bills (\$1,200) leaves \$800 usable buffer. You are \$${state.emergencyGap.toStringAsFixed(0)} short for this scenario."
                              : "Liquid funds are sufficient to cover this emergency without compromising your committed upcoming bills.",
                          style: TextStyle(
                            fontSize: 11.5,
                            color: state.emergencyGap > 0 ? AppTheme.riskRedText : AppTheme.successGreenText,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const DisclaimerBanner(
                    text: "Protection Boundary: Protected bills are reserved and never treated as spendable cash. Emergency scenarios reflect hypothetical planning.",
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
