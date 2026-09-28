import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/maps/marker_icon_renderer.dart';
import 'package:meet_commerce_rider_main/core/maps/rider_map.dart';
import 'package:meet_commerce_rider_main/core/maps/rider_maps_service.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_map_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:mocktail/mocktail.dart';

class _MockMaps extends Mock implements RiderMapsService {}

// A road-shaped (L, not straight) route: west along a street, then south.
const GeoPoint _start = GeoPoint(22.6000, 88.3600);
const GeoPoint _corner = GeoPoint(22.6000, 88.3500);
const GeoPoint _store = GeoPoint(22.5700, 88.3500);
const GeoPoint _customer = GeoPoint(22.5500, 88.3300);

RiderRoute _lRoute({int distance = 4400, int seconds = 600}) => RiderRoute(
  points: const <GeoPoint>[_start, _corner, _store],
  distanceMeters: distance,
  durationSeconds: seconds,
);

DeliveryOrder _order(AssignmentStatus status) => DeliveryOrder(
  orderId: 'order-1',
  orderNumber: 'FC-KOL-20260928-0004',
  assignmentStatus: status,
  totalAmount: 100,
  paymentMethod: 'COD',
  riderEarning: 25,
  estimatedDuration: 12,
  customerAddress: DeliveryAddress(
    name: 'Customer',
    address: 'Drop',
    lat: 22.5500,
    lng: 88.3300,
  ),
  storeAddress: DeliveryAddress(
    name: 'FreshCuts — Kolkata',
    address: 'Pickup',
    lat: 22.5700,
    lng: 88.3500,
  ),
  items: const <DeliveryItem>[],
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _MockMaps maps;
  late DateTime now;
  late ActiveDeliveryMapController controller;

  setUpAll(() => registerFallbackValue(const GeoPoint(1, 1)));

  setUp(() {
    maps = _MockMaps();
    now = DateTime(2026, 9, 28, 12);
    controller = ActiveDeliveryMapController(
      mapsService: maps,
      clock: () => now,
    );
  });

  test('a GPS fix that arrives AFTER the order still triggers the route',
      () async {
    when(() => maps.getRoute(any(), any())).thenAnswer((_) async => _lRoute());

    controller.applyOrder(_order(AssignmentStatus.accepted), null);
    expect(controller.routeStatus, MapRouteStatus.awaitingLocation);
    expect(controller.route, isNull);
    expect(controller.distanceMeters, isNull, reason: 'no fake estimate');
    verifyNever(() => maps.getRoute(any(), any()));

    controller.updateRiderPosition(_start);
    expect(controller.routeStatus, MapRouteStatus.loading);
    await _settle();

    verify(() => maps.getRoute(_start, _store)).called(1);
    expect(controller.routeStatus, MapRouteStatus.ready);
    expect(controller.route!.points, hasLength(greaterThanOrEqualTo(3)));
    expect(controller.distanceMeters, closeTo(4400, 1));
    expect(controller.etaMinutes, 10, reason: 'Ola duration 600 s');
  });

  test('distance / ETA count down along the route and the line is trimmed',
      () async {
    when(() => maps.getRoute(any(), any())).thenAnswer((_) async => _lRoute());
    controller.updateRiderPosition(_start);
    controller.applyOrder(_order(AssignmentStatus.accepted), null);
    await _settle();

    // Halfway down the second leg (on the road).
    controller.updateRiderPosition(const GeoPoint(22.5850, 88.3500));

    expect(controller.distanceMeters, inInclusiveRange(1600, 1750));
    expect(controller.etaMinutes, inInclusiveRange(3, 5));
    // The travelled leg is gone: line starts at the rider and has 2 points
    // (snapped position → store).
    expect(controller.route!.points, hasLength(2));
    expect(controller.route!.points.last, _store);
    expect(controller.route!.points.first.latitude, closeTo(22.5850, 1e-6));
    expect(
      controller.overviewToken,
      1,
      reason: 'moving along the route must not re-frame the camera',
    );
  });

  test('a failed fetch draws NOTHING and reports failed; retry recovers',
      () async {
    when(() => maps.getRoute(any(), any())).thenAnswer((_) async => null);
    controller.updateRiderPosition(_start);
    controller.applyOrder(_order(AssignmentStatus.accepted), null);
    await _settle();

    expect(controller.routeStatus, MapRouteStatus.failed);
    expect(controller.route, isNull, reason: 'never a straight line');
    expect(controller.distanceMeters, isNull);
    expect(controller.etaMinutes, isNull);

    when(() => maps.getRoute(any(), any())).thenAnswer((_) async => _lRoute());
    controller.retryRoute();
    await _settle();
    expect(controller.routeStatus, MapRouteStatus.ready);
    expect(controller.route, isNotNull);
  });

  test('pickup → customer clears the old route and fetches a fresh one',
      () async {
    when(() => maps.getRoute(any(), any())).thenAnswer((_) async => _lRoute());
    controller.updateRiderPosition(_start);
    controller.applyOrder(_order(AssignmentStatus.accepted), null);
    await _settle();
    expect(controller.overviewToken, 1);

    // Rider is at the store, scans, order goes in transit.
    controller.updateRiderPosition(_store);
    final Completer<RiderRoute?> toCustomer = Completer<RiderRoute?>();
    when(
      () => maps.getRoute(any(), _customer),
    ).thenAnswer((_) => toCustomer.future);
    controller.applyOrder(_order(AssignmentStatus.inTransit), null);

    // The pickup route must be gone the instant the destination changes.
    expect(controller.phase, LocationPhase.toCustomer);
    expect(controller.route, isNull);
    expect(controller.distanceMeters, isNull);
    expect(controller.routeStatus, MapRouteStatus.loading);
    verify(() => maps.getRoute(_store, _customer)).called(1);

    toCustomer.complete(
      const RiderRoute(
        points: <GeoPoint>[_store, GeoPoint(22.5600, 88.3400), _customer],
        distanceMeters: 5000,
        durationSeconds: 900,
      ),
    );
    await _settle();

    expect(controller.routeStatus, MapRouteStatus.ready);
    expect(controller.route!.points.last, _customer);
    expect(controller.etaMinutes, 15);
    expect(controller.overviewToken, 2, reason: 're-frame for the new leg');
    final List<String> ids = controller.markers
        .map((RiderMarkerSpec m) => m.id)
        .toList();
    expect(ids, containsAll(<String>['rider', 'customer']));
    expect(ids, isNot(contains('store')));
  });

  test('a slow route for the OLD destination never overwrites the new one',
      () async {
    final Completer<RiderRoute?> slowStoreRoute = Completer<RiderRoute?>();
    when(
      () => maps.getRoute(any(), _store),
    ).thenAnswer((_) => slowStoreRoute.future);
    when(() => maps.getRoute(any(), _customer)).thenAnswer(
      (_) async => const RiderRoute(
        points: <GeoPoint>[_store, _customer],
        distanceMeters: 3000,
        durationSeconds: 300,
      ),
    );
    controller.updateRiderPosition(_store);
    controller.applyOrder(_order(AssignmentStatus.accepted), null);
    controller.applyOrder(_order(AssignmentStatus.inTransit), null);
    await _settle();

    slowStoreRoute.complete(_lRoute()); // arrives late
    await _settle();

    expect(controller.route!.points.last, _customer);
    expect(controller.routeStatus, MapRouteStatus.ready);
    expect(controller.etaMinutes, 5, reason: 'the customer route\'s 300 s');
  });

  test('going off route reroutes from the rider, throttled, without a jump',
      () async {
    when(() => maps.getRoute(any(), any())).thenAnswer((_) async => _lRoute());
    controller.updateRiderPosition(_start);
    controller.applyOrder(_order(AssignmentStatus.accepted), null);
    await _settle();
    verify(() => maps.getRoute(any(), any())).called(1);

    // ~200 m west of the road. One spike alone must not reroute.
    controller.updateRiderPosition(const GeoPoint(22.5850, 88.3480));
    await _settle();
    verifyNever(() => maps.getRoute(const GeoPoint(22.5850, 88.3480), _store));

    // Still off route on the next fix → reroute, but only after the
    // throttle window since the first fetch has passed.
    now = now.add(ActiveDeliveryMapController.minRefetchInterval);
    controller.updateRiderPosition(const GeoPoint(22.5845, 88.3480));
    await _settle();
    verify(
      () => maps.getRoute(const GeoPoint(22.5845, 88.3480), _store),
    ).called(1);
    expect(controller.overviewToken, 1, reason: 'a reroute never re-frames');
    expect(controller.routeStatus, MapRouteStatus.ready);

    // More off-route fixes inside the throttle window: no request storm.
    controller.updateRiderPosition(const GeoPoint(22.5840, 88.3480));
    controller.updateRiderPosition(const GeoPoint(22.5835, 88.3480));
    await _settle();
    verifyNever(
      () => maps.getRoute(const GeoPoint(22.5840, 88.3480), _store),
    );
    verifyNever(
      () => maps.getRoute(const GeoPoint(22.5835, 88.3480), _store),
    );
  });

  test('a failed reroute keeps the previous good route on screen', () async {
    when(() => maps.getRoute(any(), any())).thenAnswer((_) async => _lRoute());
    controller.updateRiderPosition(_start);
    controller.applyOrder(_order(AssignmentStatus.accepted), null);
    await _settle();

    when(() => maps.getRoute(any(), any())).thenAnswer((_) async => null);
    now = now.add(ActiveDeliveryMapController.minRefetchInterval);
    controller.updateRiderPosition(const GeoPoint(22.5850, 88.3480));
    controller.updateRiderPosition(const GeoPoint(22.5845, 88.3480));
    await _settle();

    expect(controller.route, isNotNull);
    expect(controller.routeStatus, MapRouteStatus.ready);
  });

  test('0,0 / NaN / out-of-range fixes are ignored', () async {
    controller.updateRiderPosition(const GeoPoint(0, 0));
    controller.updateRiderPosition(const GeoPoint(double.nan, 88));
    controller.updateRiderPosition(const GeoPoint(95, 88));
    expect(controller.riderPosition, isNull);

    controller.applyOrder(_order(AssignmentStatus.accepted), null);
    expect(controller.routeStatus, MapRouteStatus.awaitingLocation);
    verifyNever(() => maps.getRoute(any(), any()));
    expect(
      controller.markers.map((RiderMarkerSpec m) => m.id),
      isNot(contains('rider')),
    );
  });

  test('heading turns the rider marker into a pointing badge; null keeps it',
      () async {
    controller.updateRiderPosition(_start);
    RiderMarkerSpec rider() =>
        controller.markers.firstWhere((RiderMarkerSpec m) => m.id == 'rider');
    expect(rider().kind, RiderMarkerKind.rider);
    expect(rider().headingDegrees, isNull);

    controller.updateRiderHeading(92);
    expect(rider().kind, RiderMarkerKind.riderHeading);
    expect(rider().headingDegrees, 92);

    controller.updateRiderHeading(null);
    expect(rider().headingDegrees, 92, reason: 'last reliable heading kept');

    controller.updateRiderHeading(-90); // normalised
    expect(rider().headingDegrees, 270);
  });

  test('delivered / cancelled orders have no route or status', () async {
    controller.updateRiderPosition(_start);
    controller.applyOrder(_order(AssignmentStatus.delivered), null);
    expect(controller.routeStatus, MapRouteStatus.none);
    expect(controller.route, isNull);
    expect(controller.phase, LocationPhase.none);
  });
}
