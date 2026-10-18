import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_service.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/autopay/autopay_plans_screen.dart';
import '../../features/autopay/autopay_review_screen.dart';
import '../../features/autopay/autopay_screen.dart';
import '../../features/bills/bills_forecast_screen.dart';
import '../../features/bills/transfer_review_screen.dart';
import '../../features/cards/card_compare_screen.dart';
import '../../features/cards/card_merchant_screen.dart';
import '../../features/emergency/emergency_results_screen.dart';
import '../../features/joint/joint_new_transfer_screen.dart';
import '../../features/joint/joint_review_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../screens/main_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static GoRouter get router => _router;

  static final GoRouter _router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: AuthService.instance,
    redirect: (context, state) {
      final isAuthenticated = AuthService.instance.isAuthenticated;
      final isLoggingIn = state.uri.path == '/login';
      final isOnboarding = state.uri.path == '/onboarding';

      if (!isAuthenticated && !isLoggingIn && !isOnboarding) {
        return '/login';
      }
      if (isAuthenticated && (isLoggingIn || isOnboarding)) {
        return '/home';
      }
      return null;
    },
    routes: [
      // Auth routes
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      // 5 Main Tabs (Inside MainShell)
      GoRoute(
        path: '/home',
        builder: (context, state) => const MainShell(initialIndex: 0),
      ),
      GoRoute(
        path: '/bills',
        builder: (context, state) => const MainShell(initialIndex: 1),
        routes: [
          GoRoute(
            path: 'forecast',
            builder: (context, state) => const BillsForecastScreen(),
          ),
          GoRoute(
            path: 'transfer/review',
            builder: (context, state) => const TransferReviewScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/cards',
        builder: (context, state) => const MainShell(initialIndex: 2),
        routes: [
          GoRoute(
            path: 'merchant',
            builder: (context, state) => const CardMerchantScreen(),
          ),
          GoRoute(
            path: 'compare',
            builder: (context, state) => const CardCompareScreen(),
          ),
          // Smart AutoPay lives inside Cards
          GoRoute(
            path: 'autopay',
            builder: (context, state) => const AutoPayScreen(),
            routes: [
              GoRoute(
                path: 'review',
                builder: (context, state) => const AutoPayReviewScreen(),
              ),
              GoRoute(
                path: 'plans',
                builder: (context, state) => const AutoPayPlansScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/joint',
        builder: (context, state) => const MainShell(initialIndex: 3),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const JointNewTransferScreen(),
          ),
          GoRoute(
            path: 'review/:id',
            builder: (context, state) {
              final reviewId = state.pathParameters['id'] ?? "rev_joint_850_01";
              return JointReviewScreen(reviewId: reviewId);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/emergency',
        builder: (context, state) => const MainShell(initialIndex: 4),
        routes: [
          GoRoute(
            path: 'results',
            builder: (context, state) => const EmergencyResultsScreen(),
          ),
        ],
      ),

      // Settings
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
