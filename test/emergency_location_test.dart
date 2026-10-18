import 'dart:convert';
import 'package:creditpilot_mobile/screens/emergency_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Cancelling location never starts a hurricane subscription', (tester) async {
    var subscriptions = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/subscribe')) subscriptions++;
      return http.Response(jsonEncode({'alert_subscribed': false}), 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: EmergencyScreen()));
      await tester.pump();
      await tester.tap(find.text('Use location and enable daily simulation'));
      await tester.pump();
      expect(find.text('Cancel location lookup'), findsOneWidget);
      await tester.tap(find.text('Cancel location lookup'));
      await tester.pump();
      expect(find.text('Location lookup cancelled. You can retry when ready.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 36));
      expect(subscriptions, 0);
      expect(find.text('Use location and enable daily simulation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
    client.close();
  });
}
