import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../auth/auth_session.dart';
import 'bills_screen.dart';
import 'cards_screen.dart';
import 'autopay_screen.dart';
import 'joint_screen.dart';
import 'emergency_screen.dart';
import 'creditpilot_chat_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  Timer? _jointTimer;
  StreamSubscription<void>? _pushOpenSubscription;
  bool _hasJoint = AuthSession.instance.hasJointAccount;
  bool _checkingJoint = false;
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    if (!AuthSession.instance.sandboxLinked && _hasJoint) {
      _currentIndex = 3;
      _visited.add(3);
    }
    _checkJoint();
    _jointTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkJoint(),
    );
    _pushOpenSubscription = PushNotificationService.instance.cashflowOpens
        .listen((_) => _openCashflowFromPush());
    if (PushNotificationService.instance.takePendingCashflowOpen()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openCashflowFromPush();
      });
    }
    // Ask once after sign-in so Cards can immediately rank nearby merchants.
    unawaited(LocationService.instance.initialize());
  }

  @override
  void dispose() {
    _jointTimer?.cancel();
    _pushOpenSubscription?.cancel();
    super.dispose();
  }

  void _openCashflowFromPush() {
    if (!mounted) return;
    setState(() {
      _currentIndex = 0;
      _visited.add(0);
    });
  }

  Future<void> _checkJoint() async {
    if (_checkingJoint) return;
    _checkingJoint = true;
    try {
      final membership = await ApiService.jointMembership();
      final hasJoint = membership['has_joint_account'] == true;
      final data = hasJoint
          ? await ApiService.jointPayments()
          : <String, dynamic>{};
      final payments = data['payments'] as List? ?? [];
      if (mounted) {
        setState(() {
          _hasJoint = hasJoint;
          _notificationCount = payments
              .where(
                (p) => membership['role'] == 'primary'
                    ? p['can_decide'] == true
                    : ['approved', 'declined', 'unknown'].contains(p['status']),
              )
              .length;
          if (!hasJoint && _currentIndex == 3) {
            _currentIndex = 2;
            _visited.remove(3);
          }
        });
      }
    } catch (_) {
      // Retain the last confirmed membership during temporary connection failures.
    } finally {
      _checkingJoint = false;
    }
  }

  int _currentIndex = 2; // Start on AutoPay (Flagship screen)
  String? _preferredAutopayAccount;
  // Only mount a screen on its first visit. IndexedStack otherwise starts all
  // five network requests at once, each previously fetching six Nessie accounts.
  final Set<int> _visited = {2};

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
  }

  void _planPaydown(String account) {
    setState(() {
      _preferredAutopayAccount = account;
      _currentIndex = 2;
      _visited.add(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleTabs = [0, 1, 2, if (_hasJoint) 3, 4];
    final screens = [
      const BillsScreen(),
      CardsScreen(onNavigateTab: _onTabTapped, onPlanPaydown: _planPaydown),
      AutoPayScreen(
        onBack: () => _onTabTapped(1),
        preferredAccount: _preferredAutopayAccount,
      ),
      const JointScreen(),
      const EmergencyScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.brandNavy,
                ),
                children: [
                  TextSpan(text: "CreditPilot "),
                  TextSpan(
                    text: "AI",
                    style: TextStyle(color: AppTheme.brandBlue),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ask CreditPilot AI',
            icon: const Icon(
              Icons.auto_awesome_outlined,
              color: AppTheme.brandBlue,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CreditPilotChatScreen(),
              ),
            ),
          ),
          if (_hasJoint)
            IconButton(
              tooltip: 'Joint account notifications',
              icon: Badge(
                isLabelVisible: _notificationCount > 0,
                label: Text('$_notificationCount'),
                child: const Icon(
                  Icons.notifications_none_outlined,
                  color: AppTheme.brandNavy,
                ),
              ),
              onPressed: () => _onTabTapped(3),
            ),
          PopupMenuButton<String>(
            tooltip: 'Account menu',
            onSelected: (value) {
              if (value == 'logout') {
                AuthSession.instance.signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  AuthSession.instance.profile?.email ??
                      AuthSession.instance.profile?.displayName ??
                      'Signed in',
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 10),
                    Text('Log out'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 14, left: 4),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFE2E8F0),
                child: Text(
                  (AuthSession.instance.profile?.displayName ?? 'Member')
                      .substring(0, 1)
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandNavy,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (int index = 0; index < screens.length; index++)
            _visited.contains(index) && (index != 3 || _hasJoint)
                ? screens[index]
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: visibleTabs.indexOf(_currentIndex),
        onTap: (index) => _onTabTapped(visibleTabs[index]),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppTheme.brandBlue,
        unselectedItemColor: AppTheme.textMuted,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Home",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.credit_card_outlined),
            activeIcon: Icon(Icons.credit_card),
            label: "Cards",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            activeIcon: Icon(Icons.insights),
            label: "AutoPay",
          ),
          if (_hasJoint)
            const BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: "Joint",
            ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined),
            activeIcon: Icon(Icons.shield),
            label: "Emergency",
          ),
        ],
      ),
    );
  }
}
