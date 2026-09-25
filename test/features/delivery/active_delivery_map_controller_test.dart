import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/maps/rider_map.dart';
import 'package:meet_commerce_rider_main/core/maps/rider_maps_service.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_map_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/store_info.dart';
import 'package:mocktail/mocktail.dart';

class _MockRiderMapsService extends Mock implements RiderMapsService {}

DeliveryOrder _order({
  required AssignmentStatus status,
  String orderId = 'order-1',
  double? storeLat,
  double? storeLng,
  double? customerLat,
  double? customerLng,
}) {
  return DeliveryOrder(
    orderId: orderId,
    orderNumber: orderId,
    assignmentStatus: status,
    totalAmount: 100,
    paymentMethod: 'COD',
    riderEarning: 50,
    estimatedDuration: 12,
    customerAddress: DeliveryAddress(
      name: 'Customer',
      address: 'Drop addr',
      lat: customerLat,
      lng: customerLng,
    ),
    storeAddress: DeliveryAddress(
      name: 'Store',
      address: 'Pickup addr',
      lat: storeLat,
      lng: storeLng,
    ),
    items: const <DeliveryItem>[],
  );
}

ActiveDeliveryMapController _newController() {
  final _MockRiderMapsService maps = _MockRiderMapsService();
  // Mirror the straight-line fallback contract: the returned route runs
  // origin → destination, so endpoint assertions read naturally.
  when(() => maps.getRoute(any(), any())).thenAnswer((
    Invocation invocation,
  ) async {
    final GeoPoint origin = invocation.positionalArguments[0] as GeoPoint;
    final GeoPoint destination = invocation.positionalArguments[1] as GeoPoint;
    return RiderRoute(
      points: <GeoPoint>[origin, destination],
      distanceMeters: GeoMeters.of(origin, destination),
      durationSeconds: 300,
    );
  });
  return ActiveDeliveryMapController(mapsService: maps);
}

class GeoMeters {
  static int of(GeoPoint a, GeoPoint b) {
    // haversine rough enough for assertions that only check > 0
    final double dLat = (b.latitude - a.latitude);
    final double dLng = (b.longitude - a.longitude);
    return ((dLat.abs() + dLng.abs()) * 111000).round();
  }
}

Future<void> _settleRouteFetch() async {
  // The route fetch is fire-and-forget; let the microtask queue run.
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUpAll(() {
    registerFallbackValue(const GeoPoint(0, 0));
  });

  group('ActiveDeliveryMapController.applyOrder (Ola route via facade)', () {
    test('ACCEPTED phase routes rider→store and frames both points', () async {
      final ActiveDeliveryMapController controller = _newController();
      controller.updateRiderPosition(const GeoPoint(12.95, 77.60));
      controller.applyOrder(
        _order(
          status: AssignmentStatus.accepted,
          storeLat: 12.97,
          storeLng: 77.59,
          customerLat: 12.93,
          customerLng: 77.62,
        ),
        null,
      );
      await _settleRouteFetch();

      expect(controller.phase, LocationPhase.toStore);
      expect(controller.route, isNotNull);
      expect(controller.route!.points.first.latitude, 12.95);
      expect(controller.route!.points.first.longitude, 77.60);
      expect(controller.route!.points.last.latitude, 12.97);
      expect(controller.route!.points.last.longitude, 77.59);
      // Fit points frame the rider and the store.
      expect(controller.fitPoints, contains(const GeoPoint(12.97, 77.59)));
      // Distance/ETA are live (road truth once the route lands).
      expect(controller.distanceMeters, greaterThan(0));
      expect(controller.etaMinutes, isNotNull);
      // Markers: rider + store, no customer in the pickup phase.
      final List<String> ids = controller.markers
          .map((RiderMarkerSpec m) => m.id)
          .toList();
      expect(ids, containsAll(<String>['rider', 'store']));
      expect(ids, isNot(contains('customer')));
    });

    test('IN_TRANSIT phase routes rider→customer', () async {
      final ActiveDeliveryMapController controller = _newController();
      controller.updateRiderPosition(const GeoPoint(12.95, 77.60));
      controller.applyOrder(
        _order(
          status: AssignmentStatus.inTransit,
          storeLat: 12.97,
          storeLng: 77.59,
          customerLat: 12.93,
          customerLng: 77.62,
        ),
        null,
      );
      await _settleRouteFetch();

      expect(controller.phase, LocationPhase.toCustomer);
      expect(controller.route!.points.last.latitude, 12.93);
      expect(controller.route!.points.last.longitude, 77.62);
    });

    test('falls back to StoreInfo coordinates when the order payload has '
        'no store coords', () async {
      final ActiveDeliveryMapController controller = _newController();
      controller.updateRiderPosition(const GeoPoint(12.95, 77.60));
      final StoreInfo store = StoreInfo(
        name: 'Hub',
        address: 'Hub address',
        lat: 12.985,
        lng: 77.575,
      );

      controller.applyOrder(
        _order(
          status: AssignmentStatus.accepted,
          customerLat: 12.93,
          customerLng: 77.62,
        ),
        store,
      );
      await _settleRouteFetch();

      expect(controller.phase, LocationPhase.toStore);
      expect(controller.storePosition, const GeoPoint(12.985, 77.575));
      expect(controller.route!.points.last, const GeoPoint(12.985, 77.575));
    });

    test('unconfigured StoreInfo (lat=0, lng=0) does not satisfy the '
        'fallback — phase becomes none and no route is drawn', () {
      final ActiveDeliveryMapController controller = _newController();
      controller.updateRiderPosition(const GeoPoint(12.95, 77.60));
      final StoreInfo unconfigured = StoreInfo(
        name: 'Hub',
        address: 'Hub address',
        lat: 0,
        lng: 0,
      );

      controller.applyOrder(
        _order(status: AssignmentStatus.accepted),
        unconfigured,
      );

      expect(controller.phase, LocationPhase.none);
      expect(controller.route, isNull);
    });

    test('missing customer coords on IN_TRANSIT flips '
        'customerLocationApproximate and draws no route', () {
      final ActiveDeliveryMapController controller = _newController();
      controller.updateRiderPosition(const GeoPoint(12.95, 77.60));

      controller.applyOrder(
        _order(
          status: AssignmentStatus.inTransit,
          storeLat: 12.97,
          storeLng: 77.59,
        ),
        null,
      );

      expect(controller.customerLocationApproximate, isTrue);
      expect(controller.customerPosition, isNull);
      expect(controller.phase, LocationPhase.none);
      expect(controller.route, isNull);
    });
  });

  group('ActiveDeliveryMapController.updateRiderPosition', () {
    test('ignores deltas under 5 m', () {
      final ActiveDeliveryMapController controller = _newController();
      int notifications = 0;
      controller.addListener(() => notifications++);

      controller.updateRiderPosition(const GeoPoint(12.95, 77.60));
      expect(notifications, 1);

      // Move ~3 m east at this latitude (1° lng ≈ 108 km, so 0.00003° ≈ 3 m).
      controller.updateRiderPosition(const GeoPoint(12.95, 77.60003));
      expect(notifications, 1, reason: 'sub-5 m delta should be dropped');
      expect(controller.riderPosition, const GeoPoint(12.95, 77.60));

      // Move ~10 m east — should publish.
      controller.updateRiderPosition(const GeoPoint(12.95, 77.60010));
      expect(notifications, 2);
      expect(controller.riderPosition, const GeoPoint(12.95, 77.60010));
    });

    test('updates the rider marker once the move clears the threshold', () {
      final ActiveDeliveryMapController controller = _newController();
      controller.updateRiderPosition(const GeoPoint(12.95, 77.60));
      controller.applyOrder(
        _order(
          status: AssignmentStatus.accepted,
          storeLat: 12.97,
          storeLng: 77.59,
        ),
        null,
      );

      controller.updateRiderPosition(const GeoPoint(12.951, 77.601));

      final RiderMarkerSpec rider = controller.markers.firstWhere(
        (RiderMarkerSpec m) => m.id == 'rider',
      );
      expect(rider.position, const GeoPoint(12.951, 77.601));
    });
  });
}
