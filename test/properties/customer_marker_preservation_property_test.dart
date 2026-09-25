// Preservation Property Tests — Valid Customer Coordinates Behavior
// Unchanged
//
// **Property 2: Preservation** - Valid Customer Coordinates Behavior
// Unchanged.
//
// For any order where customer coordinates are properly provided (both
// `customerAddress.lat` and `customerAddress.lng` are non-null), the
// fixed code SHALL produce exactly the same behavior as the original
// code, preserving customer marker display, polyline drawing, and
// navigation functionality.
//
// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**

import 'package:glados/glados.dart';

import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/maps/marker_assets.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_map_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';

/// Generator for valid latitude values in range [-90, 90].
final Generator<double> _validLatGen = any.doubleInRange(-90.0, 90.0);

/// Generator for valid longitude values in range [-180, 180].
final Generator<double> _validLngGen = any.doubleInRange(-180.0, 180.0);

/// Generator for valid coordinate pairs (lat, lng).
final Generator<(double, double)> _validCoordGen = any
    .combine2<double, double, (double, double)>(
      _validLatGen,
      _validLngGen,
      (double lat, double lng) => (lat, lng),
    );

/// Generator for assignment statuses.
final Generator<AssignmentStatus> _statusGen = any.choose<AssignmentStatus>(
  AssignmentStatus.values,
);

DeliveryOrder _orderWithValidCustomerCoords({
  required AssignmentStatus status,
  required double customerLat,
  required double customerLng,
  double? storeLat,
  double? storeLng,
}) {
  return DeliveryOrder(
    orderId: 'order-preservation-test',
    orderNumber: 'ORD-PRES-001',
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
  final MarkerAssets assets = MarkerAssets();
  // ignore: invalid_use_of_visible_for_testing_member
  assets.warmForTesting();
  return ActiveDeliveryMapController(markerAssets: assets);
}

void main() {
  group('Property 2: Preservation - Valid Customer Coordinates', () {
    Glados3<(double, double), (double, double), AssignmentStatus>(
      _validCoordGen,
      _validCoordGen,
      _statusGen,
    ).test('Test 2.1: Customer marker displayed at correct position for '
        'valid coordinates', (
      (double, double) customerCoords,
      (double, double) riderCoords,
      AssignmentStatus status,
    ) {
      MarkerAssets.resetForTesting();
      final ActiveDeliveryMapController controller = _newController();

      final (double customerLat, double customerLng) = customerCoords;
      final (double riderLat, double riderLng) = riderCoords;

      controller.updateRiderPosition(GeoPoint(riderLat, riderLng));

      final DeliveryOrder order = _orderWithValidCustomerCoords(
        status: status,
        customerLat: customerLat,
        customerLng: customerLng,
        storeLat: 12.97,
        storeLng: 77.59,
      );

      controller.applyOrder(order, null);

      expect(controller.customerPosition, isNotNull);
      expect(controller.customerPosition!.latitude, customerLat);
      expect(controller.customerPosition!.longitude, customerLng);

      final MarkerEntry? customerMarker = controller.markers['customer'];
      expect(customerMarker, isNotNull);
      expect(customerMarker!.position.latitude, customerLat);
      expect(customerMarker.position.longitude, customerLng);

      expect(controller.customerLocationApproximate, isFalse);
    });

    Glados2<(double, double), (double, double)>(
      _validCoordGen,
      _validCoordGen,
    ).test('Test 2.2: Polyline drawn from rider to customer in IN_TRANSIT '
        'with valid coordinates', (
      (double, double) customerCoords,
      (double, double) riderCoords,
    ) {
      MarkerAssets.resetForTesting();
      final ActiveDeliveryMapController controller = _newController();

      final (double customerLat, double customerLng) = customerCoords;
      final (double riderLat, double riderLng) = riderCoords;

      controller.updateRiderPosition(GeoPoint(riderLat, riderLng));

      final DeliveryOrder order = _orderWithValidCustomerCoords(
        status: AssignmentStatus.inTransit,
        customerLat: customerLat,
        customerLng: customerLng,
        storeLat: 12.97,
        storeLng: 77.59,
      );

      controller.applyOrder(order, null);

      expect(controller.phase, LocationPhase.toCustomer);
      expect(controller.polylines, isNotEmpty);
      final points = controller.polylines.last.points;
      expect(points, hasLength(2));
      expect(points.first.latitude, riderLat);
      expect(points.first.longitude, riderLng);
      expect(points.last.latitude, customerLat);
      expect(points.last.longitude, customerLng);
    });

    Glados3<(double, double), (double, double), (double, double)>(
      _validCoordGen,
      _validCoordGen,
      _validCoordGen,
    ).test('Test 2.3: Customer marker position remains unchanged during '
        'rider updates', (
      (double, double) customerCoords,
      (double, double) initialRiderCoords,
      (double, double) newRiderCoords,
    ) {
      MarkerAssets.resetForTesting();
      final ActiveDeliveryMapController controller = _newController();

      final (double customerLat, double customerLng) = customerCoords;
      final (double initialRiderLat, double initialRiderLng) =
          initialRiderCoords;
      final (double newRiderLat, double newRiderLng) = newRiderCoords;

      controller.updateRiderPosition(
        GeoPoint(initialRiderLat, initialRiderLng),
      );

      final DeliveryOrder order = _orderWithValidCustomerCoords(
        status: AssignmentStatus.inTransit,
        customerLat: customerLat,
        customerLng: customerLng,
        storeLat: 12.97,
        storeLng: 77.59,
      );

      controller.applyOrder(order, null);

      expect(controller.customerPosition, isNotNull);
      expect(controller.customerPosition!.latitude, customerLat);

      controller.updateRiderPosition(GeoPoint(newRiderLat, newRiderLng));

      expect(controller.customerPosition, isNotNull);
      expect(controller.customerPosition!.latitude, customerLat);
      expect(controller.customerPosition!.longitude, customerLng);

      final MarkerEntry? customerMarker = controller.markers['customer'];
      expect(customerMarker, isNotNull);
      expect(customerMarker!.position.latitude, customerLat);
    });

    Glados2<(double, double), AssignmentStatus>(
      _validCoordGen,
      _statusGen,
    ).test(
      'Test 2.4: Customer coordinates available for navigation when valid',
      ((double, double) customerCoords, AssignmentStatus status) {
        MarkerAssets.resetForTesting();
        final ActiveDeliveryMapController controller = _newController();

        final (double customerLat, double customerLng) = customerCoords;

        controller.updateRiderPosition(const GeoPoint(12.95, 77.60));

        final DeliveryOrder order = _orderWithValidCustomerCoords(
          status: status,
          customerLat: customerLat,
          customerLng: customerLng,
          storeLat: 12.97,
          storeLng: 77.59,
        );

        controller.applyOrder(order, null);

        expect(controller.customerPosition, isNotNull);
        expect(controller.customerPosition!.latitude, customerLat);
        expect(controller.customerPosition!.longitude, customerLng);
        expect(controller.customerLocationApproximate, isFalse);
      },
    );

    Glados<(double, double)>(_validCoordGen).test(
      'Preservation: Store location fallback logic unchanged when customer '
      'coordinates are valid',
      ((double, double) customerCoords) {
        MarkerAssets.resetForTesting();
        final ActiveDeliveryMapController controller = _newController();

        final (double customerLat, double customerLng) = customerCoords;

        controller.updateRiderPosition(const GeoPoint(12.95, 77.60));

        final DeliveryOrder order = _orderWithValidCustomerCoords(
          status: AssignmentStatus.accepted,
          customerLat: customerLat,
          customerLng: customerLng,
          storeLat: null,
          storeLng: null,
        );

        controller.applyOrder(order, null);

        expect(controller.phase, LocationPhase.none);
        expect(controller.customerPosition, isNotNull);
        expect(controller.customerPosition!.latitude, customerLat);
      },
    );

    Glados2<(double, double), AssignmentStatus>(
      _validCoordGen,
      any.choose<AssignmentStatus>(<AssignmentStatus>[
        AssignmentStatus.delivered,
        AssignmentStatus.cancelled,
      ]),
    ).test('Preservation: Polylines cleared for DELIVERED/CANCELLED statuses', (
      (double, double) customerCoords,
      AssignmentStatus terminalStatus,
    ) {
      MarkerAssets.resetForTesting();
      final ActiveDeliveryMapController controller = _newController();

      final (double customerLat, double customerLng) = customerCoords;

      controller.updateRiderPosition(const GeoPoint(12.95, 77.60));

      final DeliveryOrder order = _orderWithValidCustomerCoords(
        status: terminalStatus,
        customerLat: customerLat,
        customerLng: customerLng,
        storeLat: 12.97,
        storeLng: 77.59,
      );

      controller.applyOrder(order, null);

      expect(controller.phase, LocationPhase.none);
      expect(controller.polylines, isEmpty);
      expect(controller.customerPosition, isNotNull);
    });

    Glados<(double, double)>(_validCoordGen).test(
      'Preservation: Rider position updates throttled under 5 meters',
      ((double, double) customerCoords) {
        MarkerAssets.resetForTesting();
        final ActiveDeliveryMapController controller = _newController();

        final (double customerLat, double customerLng) = customerCoords;

        const GeoPoint initialRiderPos = GeoPoint(12.95, 77.60);
        controller.updateRiderPosition(initialRiderPos);

        final DeliveryOrder order = _orderWithValidCustomerCoords(
          status: AssignmentStatus.inTransit,
          customerLat: customerLat,
          customerLng: customerLng,
          storeLat: 12.97,
          storeLng: 77.59,
        );

        controller.applyOrder(order, null);

        int notifications = 0;
        controller.addListener(() => notifications++);

        const GeoPoint smallMove = GeoPoint(12.95, 77.60003);
        controller.updateRiderPosition(smallMove);

        expect(notifications, 0);
        expect(controller.riderPosition, initialRiderPos);

        const GeoPoint largeMove = GeoPoint(12.95, 77.60010);
        controller.updateRiderPosition(largeMove);

        expect(notifications, 1);
        expect(controller.riderPosition, largeMove);

        expect(controller.customerPosition!.latitude, customerLat);
        expect(controller.customerPosition!.longitude, customerLng);
      },
    );
  });
}
