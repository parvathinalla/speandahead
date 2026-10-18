import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
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
  Timer? _billTimer;
  bool _hasJoint = AuthSession.instance.hasJointAccount;
  bool _checkingJoint = false;
  bool _checkingBills = false;
  int _notificationCount = 0;
  Map<String, dynamic>? _billAlert;
  String? _lastBillPreview;

  @override
  void initState() {
    super.initState();
    if (!AuthSession.instance.sandboxLinked && _hasJoint) {
      _currentIndex = 3;
      _visited.add(3);
    }
    _checkJoint();
    _checkBillShortfall();
    _jointTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _checkJoint());
    _billTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => _checkBillShortfall());
  }

  @override
  void dispose() {
    _jointTimer?.cancel();
    _billTimer?.cancel();
    super.dispose();
  }

  String _dollars(dynamic value) =>
      '\$${(double.tryParse(value.toString()) ?? 0).toStringAsFixed(2)}';

  String _shortDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return value?.toString() ?? 'an upcoming date';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _billPreview(Map<String, dynamic> forecast) {
    final bill = forecast['first_shortfall_bill']?.toString() ?? 'A bill';
    final amount = _dollars(forecast['first_shortfall_amount']);
    final date = _shortDate(forecast['first_shortfall_date']);
    return 'Heads up—$bill may leave you $amount short on $date......';
  }

  Future<void> _checkBillShortfall() async {
    if (_checkingBills) return;
    _checkingBills = true;
    try {
      final dashboard = await ApiService.getDashboard();
      final forecast =
          Map<String, dynamic>.from(dashboard['bill_forecast'] as Map);
      final alert = forecast['is_shortfall'] == true ? forecast : null;
      final preview = alert == null ? null : _billPreview(alert);
      if (mounted) {
        setState(() => _billAlert = alert);
        if (preview != null && preview != _lastBillPreview) {
          _lastBillPreview = preview;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(preview),
              action: SnackBarAction(
                  label: 'Open', onPressed: _openBillNotification),
            ));
          });
        }
      }
    } catch (_) {
      // Keep the last confirmed reminder during temporary connection failures.
    } finally {
      _checkingBills = false;
    }
  }

  void _showHomeSuggestions() {
    setState(() {
      _currentIndex = 0;
      _visited.add(0);
    });
  }

  Future<void> _openBillNotification() async {
    final alert = _billAlert;
    if (alert == null || !mounted) return;
    final amount = _dollars(alert['first_shortfall_amount']);
    final bill = alert['first_shortfall_bill']?.toString() ?? 'upcoming bill';
    final date = _shortDate(alert['first_shortfall_date']);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upcoming cash shortfall'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Your checking account may be $amount short when $bill is due on $date.'),
              const SizedBox(height: 16),
              const Text('Suggested options',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.savings_outlined,
                    color: AppTheme.brandBlue),
                title: Text('Move $amount from savings'),
                subtitle: const Text('Review a savings-to-checking transfer.'),
                onTap: () => Navigator.pop(ctx, 'savings'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_add_alt_1_outlined,
                    color: AppTheme.brandBlue),
                title: const Text('Request money from a contact'),
                subtitle:
                    const Text('Prepare a request for the projected gap.'),
                onTap: () => Navigator.pop(ctx, 'contact'),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
    if (choice != null && mounted) _showHomeSuggestions();
  }

  void _openNotifications() {
    if (_billAlert != null) {
      _openBillNotification();
    } else if (_hasJoint) {
      _onTabTapped(3);
    }
  }

  Future<void> _checkJoint() async {
    if (_checkingJoint) return;
    _checkingJoint = true;
    try {
      final membership = await ApiService.jointMembership();
      final hasJoint = membership['has_joint_account'] == true;
      final data =
          hasJoint ? await ApiService.jointPayments() : <String, dynamic>{};
      final payments = data['payments'] as List? ?? [];
      if (mounted)
        setState(() {
          _hasJoint = hasJoint;
          _notificationCount = payments
              .where((p) => membership['role'] == 'primary'
                  ? p['can_decide'] == true
                  : ['approved', 'declined', 'unknown'].contains(p['status']))
              .length;
          if (!hasJoint && _currentIndex == 3) {
            _currentIndex = 2;
            _visited.remove(3);
          }
        });
    } catch (_) {
      // Retain the last confirmed membership during temporary connection failures.
    } finally {
      _checkingJoint = false;
    }
  }

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
    final visibleTabs = [0, 1, 2, if (_hasJoint) 3, 4];
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
                style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandNavy),
                children: [
                  TextSpan(text: "CreditPilot "),
                  TextSpan(
                      text: "AI", style: TextStyle(color: AppTheme.brandBlue)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ask CreditPilot AI',
            icon: const Icon(Icons.auto_awesome_outlined,
                color: AppTheme.brandBlue),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const CreditPilotChatScreen())),
          ),
          IconButton(
            tooltip: _hasJoint ? 'Joint account notifications' : 'Notifications',
            icon: Stack(
              children: [
                const Icon(Icons.notifications_none_outlined,
                    color: AppTheme.brandNavy),
                if (_billAlert != null || _notificationCount > 0)
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
            onPressed:
                _billAlert != null || _hasJoint ? _openNotifications : null,
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
                      AuthSession.instance.profile?.displayName ??
                      'Signed in')),
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
                      .substring(0, 1)
                      .toUpperCase(),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandNavy),
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
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
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
