import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/status_badge.dart';

class LoadingView extends StatelessWidget {
  final String message;

  const LoadingView({super.key, this.message = "Loading financial insights..."});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.brandBlue),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonText;
  final VoidCallback? onAction;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.buttonText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.brandBlueLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppTheme.brandBlue),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.brandNavy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (buttonText != null && onAction != null) ...[
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onAction,
                child: Text(buttonText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StaleDataBanner extends StatelessWidget {
  final VoidCallback onRefresh;

  const StaleDataBanner({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.warningAmberBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, size: 16, color: AppTheme.warningAmberText),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Data may be stale. Tap to refresh latest balances.",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.warningAmberText,
              ),
            ),
          ),
          InkWell(
            onTap: onRefresh,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                "Refresh",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.brandBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SandboxUnavailableBanner extends StatelessWidget {
  const SandboxUnavailableBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: const Row(
        children: [
          StatusBadge(type: StatusBadgeType.demoFixture, compact: true),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Sandbox unavailable. Showing truthful demo fixtures.",
              style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthExpiredDialog extends StatelessWidget {
  final VoidCallback onLogin;

  const AuthExpiredDialog({super.key, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_clock_outlined, color: AppTheme.riskRed),
          SizedBox(width: 8),
          Text("Session Expired"),
        ],
      ),
      content: const Text(
        "Your Auth0 authentication token has expired. For your security, balances have been concealed. Please sign in again to continue.",
        style: TextStyle(fontSize: 12.5),
      ),
      actions: [
        ElevatedButton(
          onPressed: onLogin,
          child: const Text("Return to Login"),
        ),
      ],
    );
  }
}
