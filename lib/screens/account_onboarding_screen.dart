import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../theme/app_theme.dart';
import '../widgets/partner_invitations.dart';

class AccountOnboardingScreen extends StatelessWidget {
  const AccountOnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = AuthSession.instance;
    final who = session.profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CreditPilot AI'),
        actions: [
          TextButton.icon(
            onPressed: session.busy ? null : session.signOut,
            icon: const Icon(Icons.logout), label: const Text('Sign out')),
        ],
      ),
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Column(children: [Card(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const CircleAvatar(
                radius: 30, backgroundColor: Color(0xFFDAEAFE),
                child: Icon(Icons.account_balance_outlined,
                  size: 30, color: AppTheme.brandBlue)),
              const SizedBox(height: 16),
              Text('Welcome, ' + (who?.displayName ?? 'Member'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22,
                  fontWeight: FontWeight.w800, color: AppTheme.brandNavy)),
              const SizedBox(height: 8),
              const Text('Your account is authenticated.',
                style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 20),
              const Text('No banking sandbox is linked yet.',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'For security, we never expose another user’s demo bank balances '
                'automatically after login. An operator must provision an '
                'individual fictional Nessie sandbox for your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, height: 1.45)),
              const SizedBox(height: 18),
              if (session.error != null) ...[
                Text(session.error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.riskRed)),
                const SizedBox(height: 12),
              ],
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: session.busy ? null : session.refreshLink,
                icon: const Icon(Icons.refresh),
                label: const Text('Check account connection'),
              )),
              const SizedBox(height: 12),
              Text('Account ID: ' + (who?.subject ?? ''),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10, color: AppTheme.textMuted)),
              const SizedBox(height: 6),
              const Text('Share this account ID only with your app administrator.',
                textAlign: TextAlign.center, style: TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary)),
            ]),
          )),
          const SizedBox(height: 14),
          const PartnerInvitations(),
          ]),
        ),
      )),
    );
  }
}
