
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/providers/app_state.dart';
import '../app/theme/app_theme.dart';
import '../core/auth/auth_service.dart';
import '../features/bills/bills_screen.dart';
import '../features/cards/cards_screen.dart';
import '../features/emergency/emergency_screen.dart';
import '../features/home/home_screen.dart';
import '../features/joint/joint_screen.dart';
import '../shared/status_badge.dart';

class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;
  late final Set<int> _visited;

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex.clamp(0, 4).toInt();
    _visited = {_currentIndex};

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (!AppState.instance.isLoaded) {
        AppState.instance.loadAllData();
      }
    });
  }

  void _onTabTapped(int index) {
    if (index < 0 || index > 4) return;

    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(onNavigateTab: _onTabTapped),
      const BillsScreen(),
      CardsScreen(onNavigateTab: _onTabTapped),
      const JointScreen(),
      const EmergencyScreen(),
    ];

    final user = AuthService.instance.currentUser;
    final state = AppState.instance;

    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: const TextSpan(
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.brandNavy,
            ),
            children: [
              TextSpan(text: 'CreditPilot '),
              TextSpan(
                text: 'AI',
                style: TextStyle(color: AppTheme.brandBlue),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: StatusBadge(
              type: state.dataSource,
              compact: true,
            ),
          ),
          IconButton(
            icon: Stack(
              children: [
                const Icon(
                  Icons.notifications_none_outlined,
                  color: AppTheme.brandNavy,
                ),
                if (state.isShortfall || state.hasPendingJointReview)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.riskRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              final message = state.isShortfall
                  ? 'You have a projected bill shortfall.'
                  : state.hasPendingJointReview
                      ? 'You have a pending joint review.'
                      : 'No current alerts.';

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            },
          ),
          GestureDetector(
            onTap: () => context.go('/settings'),
            child: Padding(
              padding: const EdgeInsets.only(
                right: 14,
                left: 4,
              ),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: AppTheme.brandBlueLight,
                child: Text(
                  user?.initials ?? 'CP',
                  style: const TextStyle(
                    fontSize: 11,
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
            _visited.contains(index)
                ? screens[index]
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
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
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month),
            label: 'Bills',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.credit_card_outlined),
            activeIcon: Icon(Icons.credit_card),
            label: 'Cards',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Joint',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined),
            activeIcon: Icon(Icons.shield),
            label: 'Emergency',
          ),
        ],
      ),
    );
  }
}
