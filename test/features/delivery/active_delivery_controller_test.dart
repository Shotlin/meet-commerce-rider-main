import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/collected_payment.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';

DeliveryOrder _order(
  String id,
  AssignmentStatus status, {
  bool quickDeliverySelected = false,
  DateTime? scheduledSlotStart,
  DateTime? createdAt,
  double? customerLat,
  double? customerLng,
}) => DeliveryOrder(
  orderId: id,
  orderNumber: id,
  assignmentStatus: status,
  totalAmount: 100.0,
  paymentMethod: 'ONLINE',
  riderEarning: 10.0,
  estimatedDuration: 10,
  customerAddress: DeliveryAddress(
    name: 'Customer',
    address: 'Addr',
    lat: customerLat,
    lng: customerLng,
  ),
  storeAddress: DeliveryAddress(name: 'Store', address: 'Store Addr'),
  items: const <DeliveryItem>[],
  quickDeliverySelected: quickDeliverySelected,
  scheduledSlotStart: scheduledSlotStart,
  createdAt: createdAt,
);

void main() {
  late ActiveDeliveryController controller;

  setUp(() {
    controller = ActiveDeliveryController();
  });

  tearDown(() {
    controller.dispose();
  });

  test('starts with no active delivery', () {
    expect(controller.current, isNull);
  });

  test('setActiveDelivery / clearActiveDelivery notify listeners', () {
    int notifyCount = 0;
    controller.addListener(() => notifyCount++);

    controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
    expect(controller.current?.orderId, 'o1');
    expect(notifyCount, 1);

    controller.clearActiveDelivery();
    expect(controller.current, isNull);
    expect(notifyCount, 2);
  });

  group('applyExternalStatus enforces monotonic walk', () {
    test('legal transition accepted → inTransit updates current', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      controller.applyExternalStatus('o1', AssignmentStatus.inTransit);
      expect(controller.current?.assignmentStatus, AssignmentStatus.inTransit);
    });

    test('illegal transition is rejected (state unchanged)', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.inTransit));
      // Illegal: inTransit → accepted
      controller.applyExternalStatus('o1', AssignmentStatus.accepted);
      expect(controller.current?.assignmentStatus, AssignmentStatus.inTransit);
    });

    test('illegal transition does NOT notify listeners', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.inTransit));
      bool notified = false;
      controller.addListener(() => notified = true);

      controller.applyExternalStatus('o1', AssignmentStatus.accepted);
      expect(notified, isFalse);
    });

    test('terminal transition delivered clears the active delivery', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.inTransit));
      controller.applyExternalStatus('o1', AssignmentStatus.delivered);
      expect(controller.current, isNull);
    });

    test('terminal transition cancelled clears the active delivery', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      controller.applyExternalStatus('o1', AssignmentStatus.cancelled);
      expect(controller.current, isNull);
    });

    test('no-op when orderId does not match current delivery', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      controller.applyExternalStatus('other', AssignmentStatus.inTransit);
      expect(controller.current?.assignmentStatus, AssignmentStatus.accepted);
    });

    test('no-op when no active delivery exists', () {
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.applyExternalStatus('o1', AssignmentStatus.accepted);
      expect(notified, isFalse);
      expect(controller.current, isNull);
    });

    test('full monotonic walk: accepted → inTransit → delivered', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));

      controller.applyExternalStatus('o1', AssignmentStatus.inTransit);
      expect(controller.current?.assignmentStatus, AssignmentStatus.inTransit);

      controller.applyExternalStatus('o1', AssignmentStatus.delivered);
      expect(controller.current, isNull);
    });

    test('idempotent self-transition does nothing observable', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.applyExternalStatus('o1', AssignmentStatus.accepted);
      expect(notified, isFalse);
      expect(controller.current?.assignmentStatus, AssignmentStatus.accepted);
    });
  });

  group('single active delivery semantics (blueprint §10)', () {
    test('activeOrder aliases current', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      expect(controller.activeOrder?.orderId, 'o1');
      controller.clearActiveDelivery();
      expect(controller.activeOrder, isNull);
    });

    test('byId only matches the active order id', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      expect(controller.byId('o1'), isNotNull);
      expect(controller.byId('o2'), isNull);
    });

    test('re-asserting the same order updates it in place', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      controller.setActiveDelivery(_order('o1', AssignmentStatus.inTransit));
      expect(controller.current?.assignmentStatus, AssignmentStatus.inTransit);
    });

    test('a DIFFERENT order replaces the active one and drops its '
        'bookkeeping (server is authoritative)', () {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      controller.recordCollectedPayment(
        'o1',
        const CollectedPayment(cashCollected: 40, upiCollected: 60),
      );
      expect(controller.collectedPaymentFor('o1'), isNotNull);

      controller.setActiveDelivery(_order('o2', AssignmentStatus.accepted));

      expect(controller.current?.orderId, 'o2');
      expect(
        controller.collectedPaymentFor('o1'),
        isNull,
        reason: 'the replaced order takes its recorded COD split with it',
      );
      expect(notifyCount, greaterThanOrEqualTo(3));
    });

    test('replace notification fires exactly once for the new order', () {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      final int afterFirst = notifyCount;
      controller.setActiveDelivery(_order('o2', AssignmentStatus.accepted));
      expect(notifyCount, afterFirst + 1);
    });

    test('clearActiveDelivery on an empty controller does not notify', () {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);
      controller.clearActiveDelivery();
      expect(notifyCount, 0);
    });

    test('remove() only reacts to the active order id', () {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      final int afterSet = notifyCount;
      controller.remove('other-order');
      expect(notifyCount, afterSet, reason: 'unrelated id must not notify');
      expect(controller.current?.orderId, 'o1');

      controller.remove('o1');
      expect(controller.current, isNull);
      expect(notifyCount, afterSet + 1);
    });

    test('isBusyFor is scoped to the active order id', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      expect(controller.isBusyFor('o1'), isFalse);
      expect(controller.isBusyFor('o2'), isFalse);
      expect(controller.isBusy, isFalse);
    });

    test('collected payment is scoped to the active order id', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.accepted));
      controller.recordCollectedPayment(
        'o1',
        const CollectedPayment(cashCollected: 100, upiCollected: 0),
      );
      expect(controller.collectedPaymentFor('o1'), isNotNull);
      expect(
        controller.collectedPaymentFor('o2'),
        isNull,
        reason: 'a different id has no recorded split',
      );

      // Recording for a non-active order is ignored.
      controller.recordCollectedPayment(
        'o2',
        const CollectedPayment(cashCollected: 1, upiCollected: 1),
      );
      expect(
        controller.collectedPaymentFor('o1')?.cashCollected,
        100,
        reason: 'the existing split must not be clobbered',
      );
    });

    test('terminal external event clears the recorded COD split too', () {
      controller.setActiveDelivery(_order('o1', AssignmentStatus.inTransit));
      controller.recordCollectedPayment(
        'o1',
        const CollectedPayment(cashCollected: 100, upiCollected: 0),
      );

      controller.applyExternalStatus('o1', AssignmentStatus.delivered);

      expect(controller.current, isNull);
      expect(controller.collectedPaymentFor('o1'), isNull);
    });
  });
}
