
import 'package:flutter/material.dart';

import 'auth/auth_session.dart';
import 'auth/auth_config.dart';
import 'screens/account_onboarding_screen.dart';
import 'screens/main_shell.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CreditPilotApp());
}

class CreditPilotApp extends StatelessWidget {
  const CreditPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CreditPilot AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) => AuthConfig.debugDemo
          ? Banner(
              message: 'LOCAL DEMO',
              location: BannerLocation.topEnd,
              child: child ?? const SizedBox.shrink(),
            )
          : child ?? const SizedBox.shrink(),
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
            body: Center(
              child: CircularProgressIndicator(),
            ),
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
