import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_service.dart';
import '../../shared/disclaimer_banner.dart';
import '../../shared/status_badge.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _safetyReserve = 100.0;
  double _jointThreshold = 500.0;
  bool _enableBillAlerts = true;
  bool _enableJointAlerts = true;
  bool _enableAutoPayReminders = true;

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Preferences & Settings"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Profile Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppTheme.brandBlue,
                        child: Text(
                          user?.initials ?? "AS",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.name ?? "Alex Smith", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
                            Text(user?.email ?? "alex.smith@example.com", style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                            const SizedBox(height: 2),
                            const StatusBadge(type: StatusBadgeType.demoFixture, compact: true),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          AuthService.instance.logout();
                          context.go('/login');
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        child: const Text("Sign Out", style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text("CHECKING SAFETY RESERVE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Minimum Cash Buffer", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
                          Text("\$${_safetyReserve.toStringAsFixed(0)}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.brandBlue)),
                        ],
                      ),
                      Slider(
                        value: _safetyReserve,
                        min: 50.0,
                        max: 500.0,
                        divisions: 9,
                        activeColor: AppTheme.brandBlue,
                        label: "\$${_safetyReserve.toStringAsFixed(0)}",
                        onChanged: (val) => setState(() => _safetyReserve = val),
                      ),
                      const Text(
                        "CreditPilot preserves this amount in checking even during aggressive card paydowns or bill payments.",
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text("JOINT ACCOUNT THRESHOLD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Unusual Amount Flag Threshold", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
                          Text("\$${_jointThreshold.toStringAsFixed(0)}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.brandBlue)),
                        ],
                      ),
                      Slider(
                        value: _jointThreshold,
                        min: 100.0,
                        max: 1000.0,
                        divisions: 9,
                        activeColor: AppTheme.brandBlue,
                        label: "\$${_jointThreshold.toStringAsFixed(0)}",
                        onChanged: (val) => setState(() => _jointThreshold = val),
                      ),
                      const Text(
                        "In-app payments above this limit trigger partner review prompt before execution.",
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text("NOTIFICATIONS & ALERTS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text("14-Day Shortfall Alerts", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      subtitle: const Text("Notify when checking balance cannot cover upcoming bills", style: TextStyle(fontSize: 10.5)),
                      value: _enableBillAlerts,
                      activeColor: AppTheme.brandBlue,
                      onChanged: (val) => setState(() => _enableBillAlerts = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text("Joint Account Partner Flags", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      subtitle: const Text("In-app notifications when partner initiates a large payment", style: TextStyle(fontSize: 10.5)),
                      value: _enableJointAlerts,
                      activeColor: AppTheme.brandBlue,
                      onChanged: (val) => setState(() => _enableJointAlerts = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text("AutoPay Pre-Statement Reminders", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      subtitle: const Text("Reminder 24 hours prior to estimated statement closing", style: TextStyle(fontSize: 10.5)),
                      value: _enableAutoPayReminders,
                      activeColor: AppTheme.brandBlue,
                      onChanged: (val) => setState(() => _enableAutoPayReminders = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const Text("DEVELOPER & TEST TOOLS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Simulate Auth0 Token Expiry", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.brandNavy)),
                      const SizedBox(height: 4),
                      const Text(
                        "Tests security boundary: ensures user is immediately returned to login without balance leaks.",
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.riskRed),
                        onPressed: () {
                          AuthService.instance.expireTokenForTesting();
                          context.go('/login');
                        },
                        child: const Text("Expire Token Now"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const DisclaimerBanner(
                text: "CreditPilot AI / SpendAhead is a financial decision simulation tool. Features do not guarantee credit score increases or bank-level payment interceptions.",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
