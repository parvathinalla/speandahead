import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../auth/auth_session.dart';
import 'bills_screen.dart';
import 'cards_screen.dart';
import 'autopay_screen.dart';
import 'joint_screen.dart';
import 'emergency_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 2; // Start on AutoPay (Flagship screen)
  // Only mount a screen on its first visit. IndexedStack otherwise starts all
  // five network requests at once, each previously fetching six Nessie accounts.
  final Set<int> _visited = {2};

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const BillsScreen(),
      CardsScreen(onNavigateTab: _onTabTapped),
      AutoPayScreen(onBack: () => _onTabTapped(1)),
      const JointScreen(),
      const EmergencyScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.brandNavy),
                children: [
                  TextSpan(text: "CreditPilot "),
                  TextSpan(text: "AI", style: TextStyle(color: AppTheme.brandBlue)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_none_outlined, color: AppTheme.brandNavy),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppTheme.riskRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            onPressed: () {},
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
                child: Text(AuthSession.instance.profile?.email ??
                    AuthSession.instance.profile?.displayName ?? 'Signed in')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 10),
                  Text('Log out'),
                ]),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 14, left: 4),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFE2E8F0),
                child: Text(
                  (AuthSession.instance.profile?.displayName ?? 'Member')
                      .substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800, color: AppTheme.brandNavy),
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
            _visited.contains(index) ? screens[index] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppTheme.brandBlue,
        unselectedItemColor: AppTheme.textMuted,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.credit_card_outlined),
            activeIcon: Icon(Icons.credit_card),
            label: "Cards",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            activeIcon: Icon(Icons.insights),
            label: "AutoPay",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: "Joint",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined),
            activeIcon: Icon(Icons.shield),
            label: "Emergency",
          ),
        ],
      ),
    );
  }
}
