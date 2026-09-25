import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/maps/marker_assets.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_map_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/store_info.dart';

DeliveryOrder _order({
  required AssignmentStatus status,
  String orderId = 'order-1',
  bool quickDeliverySelected = false,
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
    quickDeliverySelected: quickDeliverySelected,
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
  final MarkerAssets assets = MarkerAssets();
  // ignore: invalid_use_of_visible_for_testing_member
  assets.warmForTesting();
  return ActiveDeliveryMapController(markerAssets: assets);
}

void main() {
  setUp(() {
    MarkerAssets.resetForTesting();
  });

  group('ActiveDeliveryMapController.applyOrder', () {
    test('ACCEPTED phase produces a polyline rider→store (R12.2)', () {
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

      expect(controller.phase, LocationPhase.toStore);
      expect(controller.polylines, isNotEmpty);
      final fm.Polyline route = controller.polylines.last;
      expect(route.points.first.latitude, 12.95);
      expect(route.points.first.longitude, 77.60);
      expect(route.points.last.latitude, 12.97);
      expect(route.points.last.longitude, 77.59);
    });

    test('IN_TRANSIT phase produces a polyline rider→customer (R12.3)', () {
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

      expect(controller.phase, LocationPhase.toCustomer);
      expect(controller.polylines, isNotEmpty);
      final fm.Polyline route = controller.polylines.last;
      expect(route.points.first.latitude, 12.95);
      expect(route.points.last.latitude, 12.93);
      expect(route.points.last.longitude, 77.62);
    });

    test('falls back to StoreInfo coordinates when the order payload has '
        'no store coords (R12.4)', () {
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

      expect(controller.phase, LocationPhase.toStore);
      expect(controller.storePosition, const GeoPoint(12.985, 77.575));
      expect(controller.polylines.last.points.last.latitude, 12.985);
      expect(controller.polylines.last.points.last.longitude, 77.575);
    });

    test('unconfigured StoreInfo (lat=0, lng=0) does not satisfy the '
        'fallback — phase becomes none and no polyline is drawn', () {
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
      expect(controller.polylines, isEmpty);
    });

    test('missing customer coords on IN_TRANSIT flips '
        'customerLocationApproximate and does NOT display customer marker '
        '(Bug Fix - Requirements 2.1, 2.3)', () {
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
      expect(controller.polylines, isEmpty);
    });
  });

  group('ActiveDeliveryMapController.updateRiderPosition', () {
    test('ignores deltas under 5 m (R25.2)', () {
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

      final MarkerEntry? rider = controller.markers['rider'];
      expect(rider, isNotNull);
      expect(rider!.position, const GeoPoint(12.951, 77.601));
      // Polyline first endpoint follows the rider.
      expect(controller.polylines.last.points.first.latitude, 12.951);
      expect(controller.polylines.last.points.first.longitude, 77.601);
    });
  });
}
