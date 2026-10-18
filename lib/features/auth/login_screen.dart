import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_service.dart';
import '../../shared/status_badge.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _selectedProfileId = "alex_smith";
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);
    await AuthService.instance.loginWithAuth0(profileId: _selectedProfileId);
    if (mounted) {
      setState(() => _isLoading = false);
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // App Brand Header
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.brandNavy, AppTheme.brandBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brandBlue.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.brandNavy,
                  ),
                  children: [
                    TextSpan(text: "CreditPilot "),
                    TextSpan(text: "AI", style: TextStyle(color: AppTheme.brandBlue)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "SpendAhead • Financial Decision Assistant",
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const StatusBadge(type: StatusBadgeType.demoFixture, compact: true),
              const SizedBox(height: 36),

              // Auth0 Login Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 18, color: AppTheme.brandNavy),
                          SizedBox(width: 8),
                          Text(
                            "Auth0 Sandbox Login",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.brandNavy,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Select a verified demo profile to authenticate with JWT bearer tokens. No client secrets are stored on device.",
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                      ),
                      const Divider(height: 24),

                      const Text(
                        "SELECT DEMO PROFILE",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 10),

                      ...AuthService.demoProfiles.map((p) {
                        final isSelected = _selectedProfileId == p["id"];
                        return GestureDetector(
                          onTap: () => setState(() => _selectedProfileId = p["id"]!),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.brandBlueLight : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? AppTheme.brandBlue : AppTheme.borderSubtle,
                                width: isSelected ? 1.8 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isSelected ? AppTheme.brandBlue : const Color(0xFFE2E8F0),
                                  child: Text(
                                    p["initials"]!,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : AppTheme.brandNavy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p["name"]!,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.brandNavy),
                                      ),
                                      Text(
                                        "${p["role"]} • ${p["email"]}",
                                        style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: AppTheme.brandBlue, size: 20),
                              ],
                            ),
                          ),
                        );
                      }),

                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                                )
                              : const Text("Authenticate & Continue"),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => context.go('/onboarding'),
                          child: const Text("View Onboarding Walkthrough", style: TextStyle(fontSize: 11.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                "Nessie Sandbox & Auth0 Security Boundary:\nAll Nessie API keys and Auth0 secrets remain on the FastAPI backend.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: AppTheme.textMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
