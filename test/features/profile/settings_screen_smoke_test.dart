import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/features/profile/presentation/settings_screen.dart';

void main() {
  testWidgets(
    'SettingsScreen renders the toggles, help row, and version footer',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
      expect(find.text('Push notifications'), findsOneWidget);
      expect(find.text('Order alerts'), findsOneWidget);
      expect(find.text('LOCATION'), findsOneWidget);
      expect(find.text('High-precision location'), findsOneWidget);
      expect(find.text('Help & support'), findsOneWidget);
      expect(find.text('App version'), findsOneWidget);
      // Three switches: notifications, order alerts, location precision.
      expect(find.byType(Switch), findsNWidgets(3));
    },
  );

  testWidgets('SettingsScreen toggles flip on tap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final Finder firstSwitch = find.byType(Switch).first;
    final Switch before = tester.widget<Switch>(firstSwitch);
    expect(before.value, isTrue); // Default ON.
    await tester.tap(firstSwitch);
    await tester.pumpAndSettle();
    final Switch after = tester.widget<Switch>(find.byType(Switch).first);
    expect(after.value, isFalse);
  });
}
