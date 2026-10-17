import 'package:flutter/material.dart';
import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'core/auth/auth_service.dart';

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
      routerConfig: AppRouter.router,
    );
  }
}
