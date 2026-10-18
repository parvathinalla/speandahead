import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/debounced_button.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class JointReviewScreen extends StatefulWidget {
  final String reviewId;
  const JointReviewScreen({super.key, required this.reviewId});

  @override
  State<JointReviewScreen> createState() => _JointReviewScreenState();
}

class _JointReviewScreenState extends State<JointReviewScreen> {
  //String? _selectedAction;
  final TextEditingController _noteController = TextEditingController();

  Future<void> _handleSubmit(String decision) async {
    //setState(() => _selectedAction = decision);
    await AppState.instance.submitJointDecision(widget.reviewId, decision);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Payment decision '$decision' recorded successfully.")),
      );
      context.go('/joint');
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Partner Payment Review"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/joint'),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: StatusBadge(type: StatusBadgeType.pendingReview, compact: true),
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
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("PARTNER DECISION REQUEST", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                          StatusBadge(type: StatusBadgeType.pendingReview, compact: true),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Center(
                        child: Text(
                          "\$850.00",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.riskRed,
                            fontFamily: 'Plus Jakarta Sans',
                          ),
                        ),
                      ),
                      const Center(
                        child: Text(
                          "Best Buy • Electronics • Today, 10:24 AM",
                          style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                        ),
                      ),
                      const Divider(height: 24),
                      const Text(
                        "Alex Smith initiated this payment from your Joint Checking account (•••• 4321). Because this amount is above your configured threshold of \$500, CreditPilot requests partner consent before initiating.",
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text("OPTIONAL PARTNER NOTE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  hintText: "e.g., 'Approved for living room TV purchase'",
                  hintStyle: TextStyle(fontSize: 12),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              // Action 1: Approve
              DebouncedButton(
                onPressed: () => _handleSubmit("approved"),
                backgroundColor: AppTheme.successGreen,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 18),
                    SizedBox(width: 8),
                    Text("Approve Payment (\$850.00)"),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Action 2: Request Discussion
              DebouncedButton(
                onPressed: () => _handleSubmit("discussion_requested"),
                backgroundColor: AppTheme.warningAmber,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    SizedBox(width: 8),
                    Text("Request Discussion First"),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Action 3: Decline
              DebouncedButton(
                isOutlined: true,
                onPressed: () => _handleSubmit("declined"),
                foregroundColor: AppTheme.riskRed,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cancel_outlined, size: 18, color: AppTheme.riskRed),
                    SizedBox(width: 8),
                    Text("Decline This Payment", style: TextStyle(color: AppTheme.riskRed)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const DisclaimerBanner(
                text: "CreditPilot does not block transactions at the bank level; this review gate applies strictly to in-app initiated workflows.",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
