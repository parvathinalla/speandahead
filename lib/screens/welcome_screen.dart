import 'package:flutter/material.dart';

import '../auth/auth_config.dart';
import '../auth/auth_session.dart';
import '../theme/app_theme.dart';

/// The app NEVER handles user passwords. Login launches Auth0 Universal Login.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AuthSession.instance;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FE),
      body: SafeArea(
        child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF071F43), Color(0xFF1257B3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.auto_graph_rounded, color: Colors.white, size: 31),
                      SizedBox(width: 10),
                      Text('CreditPilot AI', style: TextStyle(
                        fontSize: 23, color: Colors.white,
                        fontWeight: FontWeight.w900)),
                    ]),
                    const SizedBox(height: 26),
                    const Text('Know your next move.',
                      style: TextStyle(color: Colors.white,
                        fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 9),
                    const Text(
                      'Understand upcoming bills, safer card choices, '
                      'and emergency readiness before you spend.',
                      style: TextStyle(color: Color(0xFFD7E7FC), height: 1.5)),
                    const SizedBox(height: 18),
                    const Row(children: [
                      Icon(Icons.verified_user_outlined,
                        color: Color(0xFFB8DBFF), size: 17),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                        'Secure sign-in powered by Auth0 Universal Login',
                        style: TextStyle(color: Color(0xFFE0ECFF), fontSize: 12))),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 21),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Welcome', style: TextStyle(
                        color: AppTheme.brandNavy, fontSize: 23,
                        fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text('Already have an account? Log in to continue.',
                        style: TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 22),
                      if (session.configurationError != null) ...[
                        Container(padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.riskRedBg,
                            borderRadius: BorderRadius.circular(9)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Auth0 configuration required',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(session.configurationError!,
                                style: const TextStyle(fontSize: 12)),
                            ],
                          )),
                        const SizedBox(height: 14),
                      ],
                      if (session.error != null) ...[
                        Text(session.error!,
                          style: const TextStyle(color: AppTheme.riskRed,
                            fontSize: 12)),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        onPressed: session.busy || session.configurationError != null
                          ? null : () => session.signIn(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Text(session.busy ? 'Please wait…' : 'Log In'),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        AuthConfig.debugDemo
                            ? 'DEBUG ONLY: fictional demo login enabled.'
                            : 'Authentication uses PKCE and hosted Auth0 screens. '
                              'No passwords are entered into CreditPilot.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                    ]),
                ),
              ),
              const SizedBox(height: 12),
              const Text('CreditPilot is a financial planning prototype. '
                'Connecting real bank accounts requires a separate authorized provider.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                textAlign: TextAlign.center),
            ]),
          ),
        )),
      ),
    );
  }
}
