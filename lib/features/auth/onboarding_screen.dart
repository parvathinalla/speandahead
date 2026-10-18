import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/status_badge.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _slides = [
    {
      "icon": Icons.calendar_month_rounded,
      "title": "14-Day Bill Shortfall Forecasting",
      "subtitle": "Checking vs. Upcoming Bills",
      "desc":
          "CreditPilot compares your checking balance (\$450) with verified bills due (\$620) to warn of shortfalls early (- \$170 warning) before overdraft fees hit.",
      "badge": StatusBadgeType.liveNessie,
    },
    {
      "icon": Icons.credit_card_rounded,
      "title": "Smart Card Rewards & Utilization",
      "subtitle": "Maximize Cashback & Keep Credit Healthy",
      "desc":
          "Modeled credit cards compare rewards in real dollars alongside post-purchase utilization changes. Never trade credit profile health for pennies in rewards.",
      "badge": StatusBadgeType.simulation,
    },
    {
      "icon": Icons.insights_rounded,
      "title": "Smart Utilization AutoPay",
      "subtitle": "Safe, Early Paydown Calculations",
      "desc":
          "Calculates safe paydowns toward your target utilization (e.g. 29%). If a \$460 paydown would compromise your checking buffer, safely limits it to \$250.",
      "badge": StatusBadgeType.simulation,
    },
    {
      "icon": Icons.people_alt_rounded,
      "title": "Joint Account Transparency",
      "subtitle": "In-App Coordination for Outliers",
      "desc":
          "Flags unusual transactions (like an \$850 electronics purchase) and prompts your partner for consent prior to in-app execution.",
      "badge": StatusBadgeType.pendingReview,
    },
    {
      "icon": Icons.shield_rounded,
      "title": "Emergency Readiness Calculator",
      "subtitle": "Liquid Funds vs Protected Commitments",
      "desc":
          "Tests whether your funds (\$2,000) can survive a \$1,000 emergency after setting aside \$1,200 for protected bills.",
      "badge": StatusBadgeType.demoFixture,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text("Skip to Login", style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (context, index) {
                  final s = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppTheme.brandBlueLight,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(s["icon"] as IconData, size: 40, color: AppTheme.brandBlue),
                        ),
                        const SizedBox(height: 24),
                        StatusBadge(type: s["badge"] as StatusBadgeType),
                        const SizedBox(height: 14),
                        Text(
                          s["title"] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.brandNavy,
                            fontFamily: 'Plus Jakarta Sans',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s["subtitle"] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandBlue,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s["desc"] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Pagination Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == i ? AppTheme.brandBlue : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentPage < _slides.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      context.go('/login');
                    }
                  },
                  child: Text(_currentPage == _slides.length - 1 ? "Get Started" : "Next"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
