import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_profile.dart';
import 'package:meet_commerce_rider_main/features/profile/presentation/profile_screen.dart';

/// Stub [DeliveryApi] that returns a fixed [RiderProfile] from
/// `getProfile`. All other methods throw, which keeps the test
/// honest about what the screen actually exercises.
class _StubProfileApi implements DeliveryApi {
  _StubProfileApi(this._profile);
  final RiderProfile _profile;

  @override
  Future<RiderProfile> getProfile() async => _profile;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in smoke test');
}

void main() {
  testWidgets('ProfileScreen renders typed RiderProfile fields', (
    WidgetTester tester,
  ) async {
    const RiderProfile profile = RiderProfile(
      id: 'rider-1',
      userId: 'user-1',
      vehicleType: 'BIKE',
      vehicleNumber: 'WB02 AB 1234',
      isApproved: true,
      isOnline: false,
      rating: 4.7,
      totalDeliveries: 42,
      commissionRate: 15.0,
      name: 'Priya Nair',
      phone: '9999999999',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          deliveryApiProvider.overrideWithValue(_StubProfileApi(profile)),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Priya Nair'), findsOneWidget);
    expect(find.text('+91 9999999999'), findsOneWidget);
    expect(find.text('4.7'), findsOneWidget); // rating
    expect(find.text('42'), findsOneWidget); // total deliveries
    expect(find.text('BIKE'), findsOneWidget);
    expect(find.text('WB02 AB 1234'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('ProfileScreen renders "Not set" when vehicle fields are null', (
    WidgetTester tester,
  ) async {
    const RiderProfile profile = RiderProfile(
      id: 'rider-1',
      userId: 'user-1',
      isApproved: false,
      isOnline: false,
      rating: 0,
      totalDeliveries: 0,
      commissionRate: 15.0,
      name: 'Rider',
      phone: '9999999999',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          deliveryApiProvider.overrideWithValue(_StubProfileApi(profile)),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Two "Not set" rows: vehicle type + vehicle number.
    expect(find.text('Not set'), findsNWidgets(2));
  });
}
