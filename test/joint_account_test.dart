import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:creditpilot_mobile/screens/main_shell.dart';
import 'package:creditpilot_mobile/screens/joint_screen.dart';

void main() {
  for (final role in ['individual', 'primary', 'dependent']) {
    testWidgets('Joint navigation and actions for $role', (tester) async {
      final client = MockClient((request) async {
        final Object payload;
        if (request.url.path == '/api/joint/membership') {
          payload = {
            'has_joint_account': role != 'individual',
            'role': role,
            'account_name': 'Family checking',
            'threshold': 500,
            'execution_enabled': true,
            'recipients': [
              {'id': 'store', 'name': 'Sandbox store'},
            ],
          };
        } else if (request.url.path == '/api/joint/payments') {
          payload = {
            'payments': [
              {
                'id': 'test-request',
                'merchant': 'Sandbox store',
                'amount': 600,
                'reason': 'Shopping',
                'status': role == 'primary' ? 'awaiting_primary' : 'approved',
                'can_decide': role == 'primary',
                'can_execute': role == 'dependent',
                'assessment': {'reason': 'Amount review', 'over_limit': true},
              },
            ],
          };
        } else {
          payload = {'cards': []};
        }
        return http.Response(jsonEncode(payload), 200,
            headers: {'content-type': 'application/json'});
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: MainShell()));
        await tester.pumpAndSettle();
        expect(find.text('Joint'), role == 'individual' ? findsNothing : findsOneWidget);
        expect(find.byTooltip('Joint account notifications'),
            role == 'individual' ? findsNothing : findsOneWidget);
        if (role != 'individual') {
          await tester.tap(find.text('Joint'));
          await tester.pumpAndSettle();
          expect(find.text('Save approval limit'),
              role == 'primary' ? findsOneWidget : findsNothing);
          // Payment cards may be below the viewport, but their controls must be
          // constructed only for the authenticated account role.
          await tester.scrollUntilVisible(
              find.text(role == 'primary' ? 'Approve' : 'Proceed with payment'), 250,
              scrollable: find.descendant(of: find.byType(JointScreen),
                matching: find.byType(Scrollable)).first);
          await tester.pumpAndSettle();
          expect(find.text('Approve'), role == 'primary' ? findsOneWidget : findsNothing);
          expect(find.text('Decline'), role == 'primary' ? findsOneWidget : findsNothing);
          expect(find.text('Proceed with payment'),
              role == 'dependent' ? findsOneWidget : findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        // Finish any location lookup started by a visited tab.
        await tester.pump(const Duration(seconds: 21));
      }, () => client);
      client.close();
    });
  }
}
