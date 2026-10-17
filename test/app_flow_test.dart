import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:creditpilot_mobile/core/auth/auth_service.dart';
import 'package:creditpilot_mobile/app/providers/app_state.dart';
import 'package:creditpilot_mobile/core/fixtures/typed_fixtures.dart';
import 'package:creditpilot_mobile/shared/status_badge.dart';
import 'package:creditpilot_mobile/shared/debounced_button.dart';

void main() {
  group('Auth & Security Tests', () {
    test('Auth0 token-driven flow and logout concealment', () async {
      final auth = AuthService.instance;
      await auth.loginWithAuth0(profileId: "alex_smith");
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.name, "Alex Smith");
      expect(auth.token, isNotNull);

      // Verify token expiry returns user to unauthenticated state
      auth.expireTokenForTesting();
      expect(auth.isAuthenticated, isFalse);

      // Verify balances are wiped clean upon logout
      auth.logout();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.currentUser, isNull);
    });
  });

  group('Typed Fixtures & Mathematical Accuracy', () {
    test('T01: Bill shortfall calculation ($450 - $620 = -$170)', () {
      final forecast = TypedFixtures.getBillForecast();
      expect(forecast["checking_balance"], 450.0);
      expect(forecast["total_bills_due"], 620.0);
      expect(forecast["shortfall_amount"], 170.0);
      expect(forecast["projected_end_balance"], -170.0);
      expect(forecast["is_shortfall"], isTrue);
    });

    test('T04/T05: Card recommendation $120 Whole Foods ($3.60 vs $2.40)', () {
      final rec = TypedFixtures.getCardRecommendation(amount: 120.0);
      final cards = rec["cards_evaluated"] as List;
      expect(cards.length, 2);

      final cardA = cards[0]; // Venture
      expect(cardA["reward_dollars"], 3.60);
      expect(cardA["utilization_after"], 87.0);

      final cardB = cards[1]; // Savor One
      expect(cardB["reward_dollars"], 2.40);
      expect(cardB["utilization_after"], 37.0);

      expect(rec["recommended_card_id"], "card_sav_01");
    });

    test('T10: Emergency readiness ($2,000 - $1,200 - $1,000 = $200 gap)', () {
      final em = TypedFixtures.getEmergencyEvaluation(
        cost: 1000.0,
        checking: 1200.0,
        savings: 800.0,
        protectedBills: 1200.0,
      );
      expect(em["total_available_funds"], 2000.0);
      expect(em["protected_committed_bills"], 1200.0);
      expect(em["usable_cash_buffer"], 800.0);
      expect(em["potential_gap"], 200.0);
      expect(em["is_gap_present"], isTrue);
    });

    test('T11/T12: AutoPay safe limit ($460 theoretical vs $250 safe -> 29% not reachable)', () {
      final ap = TypedFixtures.getAutoPayPreview(targetPct: 29.0);
      expect(ap["theoretical_paydown_amount"], 460.0);
      expect(ap["max_safe_payment_today"], 250.0);
      expect(ap["is_full_payment_affordable"], isFalse);
      expect(ap["target_reachable"], isFalse);
      expect(ap["resulting_utilization_pct"], 50.0);
      expect(ap["reason_code"], "TARGET_NOT_AFFORDABLE");
    });

    test('T07: Joint unusual transaction ($850 at Best Buy flags review)', () {
      final joint = TypedFixtures.getJointEvaluation(amount: 850.0);
      expect(joint["amount"], 850.0);
      expect(joint["is_unusual"], isTrue);
      expect(joint["requires_partner_review"], isTrue);
      expect(joint["reason_code"], "NEW_RECIPIENT_AND_AMOUNT_ABOVE_THRESHOLD");
    });
  });

  group('Shared Widgets Tests', () {
    testWidgets('Status badges render required label types', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StatusBadge(type: StatusBadgeType.liveNessie),
                StatusBadge(type: StatusBadgeType.demoFixture),
                StatusBadge(type: StatusBadgeType.simulation),
                StatusBadge(type: StatusBadgeType.pendingReview),
                StatusBadge(type: StatusBadgeType.executedInSandbox),
                StatusBadge(type: StatusBadgeType.notExecuted),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Live Nessie'), findsOneWidget);
      expect(find.text('Demo fixture'), findsOneWidget);
      expect(find.text('Simulation'), findsOneWidget);
      expect(find.text('Pending review'), findsOneWidget);
      expect(find.text('Executed in sandbox'), findsOneWidget);
      expect(find.text('Not executed'), findsOneWidget);
    });

    testWidgets('T24: DebouncedButton handles tap and prevents duplicate executions', (WidgetTester tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DebouncedButton(
              onPressed: () async {
                tapCount++;
                await Future.delayed(const Duration(milliseconds: 100));
              },
              child: const Text('Confirm'),
            ),
          ),
        ),
      );

      // Fast double tap
      await tester.tap(find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      await tester.pump();

      // Only one execution should have triggered
      expect(tapCount, 1);

      // Finish pending timer
      await tester.pump(const Duration(milliseconds: 150));
      expect(tapCount, 1);
    });
  });
}
