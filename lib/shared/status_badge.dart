import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';

enum StatusBadgeType {
  liveNessie,
  demoFixture,
  simulation,
  pendingReview,
  executedInSandbox,
  notExecuted,
}

class StatusBadge extends StatelessWidget {
  final StatusBadgeType type;
  final String? customLabel;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.type,
    this.customLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;
    Color border;
    IconData icon;
    String label;

    switch (type) {
      case StatusBadgeType.liveNessie:
        bg = AppTheme.brandBlueLight;
        text = AppTheme.brandBlue;
        border = const Color(0xFFBFDBFE);
        icon = Icons.cloud_done_rounded;
        label = "Live Nessie";
        break;
      case StatusBadgeType.demoFixture:
        bg = const Color(0xFFF1F5F9);
        text = const Color(0xFF475569);
        border = const Color(0xFFCBD5E1);
        icon = Icons.layers_outlined;
        label = "Demo fixture";
        break;
      case StatusBadgeType.simulation:
        bg = AppTheme.simulationPurpleBg;
        text = AppTheme.simulationPurpleText;
        border = const Color(0xFFDDD6FE);
        icon = Icons.auto_graph_rounded;
        label = "Simulation";
        break;
      case StatusBadgeType.pendingReview:
        bg = AppTheme.warningAmberBg;
        text = AppTheme.warningAmberText;
        border = const Color(0xFFFDE68A);
        icon = Icons.pending_actions_rounded;
        label = "Pending review";
        break;
      case StatusBadgeType.executedInSandbox:
        bg = AppTheme.successGreenBg;
        text = AppTheme.successGreenText;
        border = const Color(0xFFA7F3D0);
        icon = Icons.check_circle_outline_rounded;
        label = "Executed in sandbox";
        break;
      case StatusBadgeType.notExecuted:
        bg = AppTheme.riskRedBg;
        text = AppTheme.riskRedText;
        border = const Color(0xFFFECACA);
        icon = Icons.cancel_outlined;
        label = "Not executed";
        break;
    }

    final displayText = customLabel ?? label;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 10 : 12, color: text),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(
              fontSize: compact ? 9.5 : 11,
              fontWeight: FontWeight.w700,
              color: text,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
