// Bug Condition Exploration Test — Customer Marker Displayed at Rider
// Position When Coordinates Missing
//
// **Property 1: Bug Condition** - Customer Marker Displayed at Rider
// Position When Coordinates Missing
//
// For any order where customer coordinates are null
// (`customerAddress.lat` is null OR `customerAddress.lng` is null), the
// UNFIXED `applyOrder` method incorrectly displays a customer marker at
// the rider's position instead of not displaying it at all.
//
// **Expected Behavior (after fix)**:
// - No customer marker displayed when coordinates are missing
// - `customerPosition` should be null
// - No customer marker in the markers set
// - `customerLocationApproximate` should be TRUE
//
// **Validates: Requirements 1.1, 2.1**

import 'package:glados/glados.dart';

import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/maps/marker_assets.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_map_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';

DeliveryOrder _orderWithNullCustomerCoords({
  required AssignmentStatus status,
  double? storeLat,
  double? storeLng,
}) {
  return DeliveryOrder(
    orderId: 'order-bug-test',
    orderNumber: 'ORD-BUG-001',
    assignmentStatus: status,
    totalAmount: 100,
    paymentMethod: 'COD',
    riderEarning: 50,
    estimatedDuration: 12,
    customerAddress: DeliveryAddress(
      name: 'Customer',
      address: 'Drop addr',
      lat: null,
      lng: null,
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
  group('Property 1: Bug Condition - Customer Marker at Rider Position', () {
    Glados<AssignmentStatus>(
      any.choose<AssignmentStatus>(AssignmentStatus.values),
    ).test('Bug Condition: Customer marker should NOT be displayed when '
        'customer coordinates are missing', (AssignmentStatus status) {
      MarkerAssets.resetForTesting();
      final ActiveDeliveryMapController controller = _newController();

      const GeoPoint riderPos = GeoPoint(12.9716, 77.5946);
      controller.updateRiderPosition(riderPos);

      final DeliveryOrder order = _orderWithNullCustomerCoords(
        status: status,
        storeLat: 12.97,
        storeLng: 77.59,
      );

      controller.applyOrder(order, null);

      expect(
        controller.customerPosition,
        isNull,
        reason:
            'customerPosition should be null when customer coordinates '
            'are missing',
      );

      expect(
        controller.markers.containsKey('customer'),
        isFalse,
        reason:
            'markers should NOT contain a customer entry when '
            'customer coordinates are missing',
      );

      expect(
        controller.customerLocationApproximate,
        isTrue,
        reason:
            'customerLocationApproximate should be true when customer '
            'coordinates are missing',
      );

      if (status == AssignmentStatus.inTransit) {
        expect(
          controller.polylines,
          isEmpty,
          reason:
              'polylines should be empty when customer coordinates are '
              'missing in IN_TRANSIT phase',
        );
        expect(
          controller.phase,
          LocationPhase.none,
          reason:
              'phase should be none when customer coordinates are '
              'missing in IN_TRANSIT phase',
        );
      }
    });

    Glados<int>(any.int).test(
      'Bug Condition: Customer marker should NOT follow rider movement '
      'when customer coordinates are missing',
      (int _) {
        MarkerAssets.resetForTesting();
        final ActiveDeliveryMapController controller = _newController();

        const GeoPoint initialRiderPos = GeoPoint(12.9716, 77.5946);
        controller.updateRiderPosition(initialRiderPos);

        final DeliveryOrder order = _orderWithNullCustomerCoords(
          status: AssignmentStatus.inTransit,
          storeLat: 12.97,
          storeLng: 77.59,
        );

        controller.applyOrder(order, null);
        expect(controller.customerPosition, isNull);

        const GeoPoint newRiderPos = GeoPoint(12.9800, 77.6000);
        controller.updateRiderPosition(newRiderPos);

        expect(
          controller.customerPosition,
          isNull,
          reason:
              'customerPosition should remain null after rider movement '
              'when customer coordinates are missing',
        );

        expect(
          controller.markers.containsKey('customer'),
          isFalse,
          reason:
              'markers should still NOT contain a customer entry '
              'after rider movement',
        );
      },
    );

    Glados<int>(any.int).test(
      'Bug Condition: Concrete example from design - IN_TRANSIT with null '
      'customer coordinates',
      (int _) {
        MarkerAssets.resetForTesting();
        final ActiveDeliveryMapController controller = _newController();

        const GeoPoint riderPos = GeoPoint(12.9716, 77.5946);
        controller.updateRiderPosition(riderPos);

        final DeliveryOrder order = _orderWithNullCustomerCoords(
          status: AssignmentStatus.inTransit,
          storeLat: 12.97,
          storeLng: 77.59,
        );

        controller.applyOrder(order, null);

        expect(controller.customerPosition, isNull);
        expect(controller.markers.containsKey('customer'), isFalse);
        expect(controller.customerLocationApproximate, isTrue);
        expect(controller.polylines, isEmpty);
        expect(controller.phase, LocationPhase.none);
      },
    );
  });
}
