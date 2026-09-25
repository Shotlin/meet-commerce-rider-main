import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/location/rider_location_provider.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/maps/rider_map.dart';
import 'package:meet_commerce_rider_main/core/maps/rider_maps_service.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/core/utils/external_nav_launcher.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_map_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_repository.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/store_info.dart';
import 'package:meet_commerce_rider_main/features/delivery/presentation/active_delivery_map_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/recording_url_launcher.dart';

class _MockDeliveryRepository extends Mock implements DeliveryRepository {}

class _MockRiderMapsService extends Mock implements RiderMapsService {}

class _Coords {
  const _Coords(this.lat, this.lng);
  final double lat;
  final double lng;
}

DeliveryOrder _orderFor({
  required AssignmentStatus status,
  required _Coords store,
  required _Coords customer,
}) {
  return DeliveryOrder(
    orderId: 'order-1',
    orderNumber: 'ORD-001',
    assignmentStatus: status,
    totalAmount: 540.0,
    paymentMethod: 'COD',
    riderEarning: 65.0,
    estimatedDuration: 18,
    customerAddress: DeliveryAddress(
      name: 'Priya N',
      address: '12 MG Road',
      lat: customer.lat,
      lng: customer.lng,
    ),
    storeAddress: DeliveryAddress(
      name: 'FreshCuts Indiranagar',
      address: '100 Feet Rd',
      lat: store.lat,
      lng: store.lng,
    ),
    items: const <DeliveryItem>[],
  );
}

Future<
  ({
    ActiveDeliveryController active,
    ActiveDeliveryMapController map,
    ValueNotifier<GeoPoint?> riderLocation,
  })
>
_pumpScreen(WidgetTester tester, {required DeliveryOrder initial}) async {
  final ActiveDeliveryController active = ActiveDeliveryController()
    ..setActiveDelivery(initial);
  final ValueNotifier<GeoPoint?> riderLocation = ValueNotifier<GeoPoint?>(
    const GeoPoint(12.95, 77.60),
  );
  final _MockDeliveryRepository repo = _MockDeliveryRepository();
  when(() => repo.getStoreInfo()).thenAnswer(
    (_) async => StoreInfo(name: 'FreshCuts', address: 'Hub', lat: 0, lng: 0),
  );
  final _MockRiderMapsService mapsService = _MockRiderMapsService();
  when(() => mapsService.getRoute(any(), any())).thenAnswer((
    Invocation invocation,
  ) async {
    final GeoPoint origin = invocation.positionalArguments[0] as GeoPoint;
    final GeoPoint destination = invocation.positionalArguments[1] as GeoPoint;
    return RiderRoute(
      points: <GeoPoint>[origin, destination],
      distanceMeters: 1000,
      durationSeconds: 200,
    );
  });
  final ActiveDeliveryMapController map = ActiveDeliveryMapController(
    mapsService: mapsService,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        activeDeliveryControllerProvider.overrideWith((Ref ref) => active),
        activeDeliveryMapControllerProvider.overrideWith((Ref ref) => map),
        riderLocationNotifierProvider.overrideWith((Ref ref) => riderLocation),
        deliveryRepositoryProvider.overrideWithValue(repo),
        externalNavLauncherProvider.overrideWithValue(
          ExternalNavigationLauncher(delegate: RecordingUrlLauncher()),
        ),
        urlLauncherDelegateProvider.overrideWithValue(RecordingUrlLauncher()),
      ],
      child: const MaterialApp(home: ActiveDeliveryMapScreen()),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));

  return (active: active, map: map, riderLocation: riderLocation);
}

void main() {
  setUpAll(() {
    registerFallbackValue(const GeoPoint(0, 0));
  });

  group('isRiderArrivedAtStore (§11 arrival state)', () {
    final DeliveryOrder order = _orderFor(
      status: AssignmentStatus.accepted,
      store: const _Coords(12.9719, 77.6412),
      customer: const _Coords(12.93, 77.62),
    );

    test('a fix within the arrival radius reads as arrived', () {
      // ~40 m from the store.
      expect(
        isRiderArrivedAtStore(
          riderPosition: const GeoPoint(12.9716, 77.6417),
          order: order,
        ),
        isTrue,
      );
    });

    test('a fix far from the store does not', () {
      expect(
        isRiderArrivedAtStore(
          riderPosition: const GeoPoint(12.9352, 77.6245),
          order: order,
        ),
        isFalse,
      );
    });

    test('without a GPS fix nothing is fabricated', () {
      expect(isRiderArrivedAtStore(riderPosition: null, order: order), isFalse);
    });
  });

  testWidgets(
    'ACCEPTED smoke test: screen renders without crashing for a fake '
    'order in ACCEPTED status (R12.1)',
    (WidgetTester tester) async {
      final DeliveryOrder accepted = _orderFor(
        status: AssignmentStatus.accepted,
        store: const _Coords(12.97, 77.59),
        customer: const _Coords(12.93, 77.62),
      );
      await _pumpScreen(tester, initial: accepted);

      expect(find.byType(ActiveDeliveryMapScreen), findsOneWidget);
      expect(find.byType(ActiveDeliveryMapScreen), findsOneWidget);
      expect(find.text('Scan pickup code'), findsOneWidget);
    },
    // Network access for tile loads is unsafe under flutter_test;
    // covered by integration_test.
    skip: true,
  );

  testWidgets(
    'switching from ACCEPTED to IN_TRANSIT swaps the polyline endpoint '
    'from store to customer (R12.2 / R12.3)',
    (WidgetTester tester) async {
      const _Coords store = _Coords(12.97, 77.59);
      const _Coords customer = _Coords(12.93, 77.62);

      final DeliveryOrder accepted = _orderFor(
        status: AssignmentStatus.accepted,
        store: store,
        customer: customer,
      );

      final result = await _pumpScreen(tester, initial: accepted);

      RiderRouteSpec? routePolyline() => result.map.route;

      expect(routePolyline()!.points.last.latitude, 12.97);

      result.active.applyExternalStatus(
        accepted.orderId,
        AssignmentStatus.inTransit,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(routePolyline()!.points.last.latitude, 12.93);
    },
    skip: true,
  );

  testWidgets('IN_TRANSIT with missing customer coordinates surfaces the '
      'error banner (Bug Fix - Requirements 2.2)', (WidgetTester tester) async {
    final DeliveryOrder inTransit = DeliveryOrder(
      orderId: 'order-1',
      orderNumber: 'ORD-001',
      assignmentStatus: AssignmentStatus.inTransit,
      totalAmount: 100,
      paymentMethod: 'COD',
      riderEarning: 50,
      estimatedDuration: 10,
      customerAddress: DeliveryAddress(
        name: 'Customer',
        address: 'Some address',
      ),
      storeAddress: DeliveryAddress(
        name: 'Store',
        address: 'Store address',
        lat: 12.97,
        lng: 77.59,
      ),
      items: const <DeliveryItem>[],
    );

    await _pumpScreen(tester, initial: inTransit);

    expect(
      find.text('Customer location unavailable - cannot navigate'),
      findsOneWidget,
    );
  }, skip: true);

  testWidgets('Navigate button is disabled when customer coordinates are null '
      '(Requirements 2.3, 3.5)', (WidgetTester tester) async {
    final DeliveryOrder inTransit = DeliveryOrder(
      orderId: 'order-1',
      orderNumber: 'ORD-001',
      assignmentStatus: AssignmentStatus.inTransit,
      totalAmount: 100,
      paymentMethod: 'COD',
      riderEarning: 50,
      estimatedDuration: 10,
      customerAddress: DeliveryAddress(
        name: 'Customer',
        address: 'Some address',
      ),
      storeAddress: DeliveryAddress(
        name: 'Store',
        address: 'Store address',
        lat: 12.97,
        lng: 77.59,
      ),
      items: const <DeliveryItem>[],
    );

    await _pumpScreen(tester, initial: inTransit);

    final Finder navigateButton = find.widgetWithText(
      MaterialButton,
      'Navigate',
    );

    expect(navigateButton, findsOneWidget);
    final MaterialButton button = tester.widget(navigateButton);
    expect(button.onPressed, isNull);
  }, skip: true);

  testWidgets('Navigate button is enabled when customer coordinates are valid '
      '(Preservation - Requirements 3.1, 3.5)', (WidgetTester tester) async {
    final DeliveryOrder inTransit = DeliveryOrder(
      orderId: 'order-1',
      orderNumber: 'ORD-001',
      assignmentStatus: AssignmentStatus.inTransit,
      totalAmount: 100,
      paymentMethod: 'COD',
      riderEarning: 50,
      estimatedDuration: 10,
      customerAddress: DeliveryAddress(
        name: 'Customer',
        address: 'Some address',
        lat: 12.93,
        lng: 77.62,
      ),
      storeAddress: DeliveryAddress(
        name: 'Store',
        address: 'Store address',
        lat: 12.97,
        lng: 77.59,
      ),
      items: const <DeliveryItem>[],
    );

    await _pumpScreen(tester, initial: inTransit);

    final Finder navigateButton = find.widgetWithText(
      MaterialButton,
      'Navigate',
    );

    expect(navigateButton, findsOneWidget);
    final MaterialButton button = tester.widget(navigateButton);
    expect(button.onPressed, isNotNull);
  }, skip: true);
}
