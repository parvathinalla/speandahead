import 'package:flutter/material.dart';

import 'auth/auth_session.dart';
import 'screens/account_onboarding_screen.dart';
import 'screens/main_shell.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize with verified demo user profile for immediate exploratory access
  await AuthService.instance.loginWithAuth0(profileId: "alex_smith");
  runApp(const CreditPilotApp());
}

class CreditPilotApp extends StatelessWidget {
  const CreditPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CreditPilot AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    AuthSession.instance.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthSession.instance,
      builder: (context, _) {
        final session = AuthSession.instance;
        if (session.initializing) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!session.signedIn) {
          return const WelcomeScreen();
        }
        if (!session.sandboxLinked) {
          return const AccountOnboardingScreen();
        }
        return const MainShell();
      },
    );
  }
}
