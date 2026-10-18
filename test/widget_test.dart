import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:creditpilot_mobile/main.dart';
import 'package:creditpilot_mobile/screens/welcome_screen.dart';

void main() {
  testWidgets('App starts behind Auth0 login gate when unconfigured',
      (WidgetTester tester) async {
    await tester.pumpWidget(const CreditPilotApp());
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('CreditPilot AI'), findsOneWidget);
    expect(find.text('Auth0 configuration required'), findsOneWidget);
    expect(find.text('Create Account'), findsNothing);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Already have an account? Log in to continue.'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });
}
