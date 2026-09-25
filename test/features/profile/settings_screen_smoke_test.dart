import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_service.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_status.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_service.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_status.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/features/profile/presentation/settings_screen.dart';

void main() {
  testWidgets(
    'SettingsScreen renders the toggles, help row, and version footer',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            // The location-status row reads the real permission state;
            // grant it so the row renders its happy path.
            locationPermissionServiceProvider.overrideWithValue(
              _StubLocationPermissionService(),
            ),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
      expect(find.text('Push notifications'), findsOneWidget);
      expect(find.text('Order alerts'), findsOneWidget);
      expect(find.text('LOCATION'), findsOneWidget);
      expect(find.text('High-precision location'), findsOneWidget);
      expect(find.text('Help & support'), findsOneWidget);
      // The ABOUT footer sits below the new LOCATION/MAPS status rows —
      // scroll to it in the default test viewport.
      await tester.scrollUntilVisible(
        find.text('App version'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('App version'), findsOneWidget);
      // Three switches: notifications, order alerts, location precision.
      expect(find.byType(Switch), findsNWidgets(3));
    },
  );

  testWidgets('SettingsScreen toggles flip on tap', (
    WidgetTester tester,
  ) async {
    // Fresh pump (the first test's scroll leaves the list mid-offset).
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // The location-status row reads the real permission state;
          // grant it so the row renders its happy path.
          locationPermissionServiceProvider.overrideWithValue(
            _StubLocationPermissionService(),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder firstSwitch = find.byType(Switch).first;
    final Switch before = tester.widget<Switch>(firstSwitch);
    expect(before.value, isTrue); // Default ON.
    await tester.ensureVisible(firstSwitch);
    await tester.pumpAndSettle();
    await tester.tap(firstSwitch);
    await tester.pumpAndSettle();
    final Switch after = tester.widget<Switch>(find.byType(Switch).first);
    expect(after.value, isFalse);
  });
}

class _StubLocationPermissionService extends _MockLocationPermissionService {
  @override
  Future<LocationPermissionResult> check() async {
    return const LocationPermissionResult(
      service: LocationServiceState.enabled,
      permission: LocationPermissionState.granted,
    );
  }
}

class _MockLocationPermissionService extends Mock
    implements LocationPermissionService {}
