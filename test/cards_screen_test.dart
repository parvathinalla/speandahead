import 'package:creditpilot_mobile/screens/cards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Cards page provides location and manual purchase modes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'initial_location_prompt_attempted': true,
    });

    await tester.pumpWidget(const MaterialApp(home: CardsScreen()));
    await tester.pump();

    expect(find.text('SpendAhead Live'), findsOneWidget);
    expect(find.text('Current location'), findsOneWidget);
    expect(find.text('Enter manually'), findsOneWidget);

    await tester.tap(find.text('Enter manually'));
    await tester.pump();

    expect(find.text('Merchant or purchase purpose'), findsOneWidget);
    expect(find.text('What-if purchase amount (USD)'), findsOneWidget);
    expect(find.text('Reward category'), findsOneWidget);
    expect(find.text('Analyze This Purchase'), findsNothing);
    expect(
      find.text(
        'Recommendations update automatically as you change the purchase.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Sandbox'), findsNothing);
    expect(find.textContaining('Demo'), findsNothing);

    expect(find.byKey(const Key('trip-copilot-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('trip-copilot-button')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Trip Spending Copilot'), findsOneWidget);
    expect(find.textContaining('Miami trip:'), findsNothing);
    expect(find.text('Planning mode'), findsOneWidget);
    expect(find.text('Protect credit'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Max rewards'), findsOneWidget);
    expect(
      find.text('One message. A complete spending strategy.'),
      findsOneWidget,
    );
    expect(find.text('Describe your trip and expected costs…'), findsOneWidget);
  });
}
