import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:creditpilot_mobile/main.dart';
import 'package:creditpilot_mobile/screens/main_shell.dart';
import 'package:creditpilot_mobile/core/auth/auth_service.dart';

void main() {
  setUp(() async {
    await AuthService.instance.loginWithAuth0(profileId: "alex_smith");
  });

  testWidgets('CreditPilotApp smoke test with 5 bottom tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const CreditPilotApp());
    await tester.pumpAndSettle();

    // Verify MainShell is mounted
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    // Verify 5 bottom tabs: Home, Bills, Cards, Joint, Emergency
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Bills'), findsWidgets);
    expect(find.text('Cards'), findsWidgets);
    expect(find.text('Joint'), findsWidgets);
    expect(find.text('Emergency'), findsWidgets);

    // Verify Brand title
    expect(find.text('CreditPilot '), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
  });
}
