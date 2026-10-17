import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:creditpilot_mobile/main.dart';
import 'package:creditpilot_mobile/screens/main_shell.dart';

void main() {
  testWidgets('CreditPilotApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CreditPilotApp());
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('AutoPay'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
  });
}
