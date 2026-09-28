import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/incoming_order_alert_decision.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';

DeliveryOrder _order(String id, AssignmentStatus status) => DeliveryOrder(
  orderId: id,
  orderNumber: id,
  assignmentStatus: status,
  totalAmount: 100.0,
  paymentMethod: 'ONLINE',
  riderEarning: 10.0,
  estimatedDuration: 10,
  customerAddress: DeliveryAddress(name: 'Customer', address: 'Addr'),
  storeAddress: DeliveryAddress(name: 'Store', address: 'Store Addr'),
  items: const <DeliveryItem>[],
);

void main() {
  group('shouldPlayIncomingOrderAlert', () {
    test('false with no offers at all', () {
      expect(
        shouldPlayIncomingOrderAlert(
          offers: const <DeliveryOrder>[],
          hasActiveDelivery: false,
        ),
        isFalse,
      );
    });

    test('true when a pending (assigned) offer exists', () {
      expect(
        shouldPlayIncomingOrderAlert(
          offers: <DeliveryOrder>[_order('o1', AssignmentStatus.assigned)],
          hasActiveDelivery: false,
        ),
        isTrue,
      );
    });

    test(
      'false once the offer moves to accepted — the rider already acted',
      () {
        expect(
          shouldPlayIncomingOrderAlert(
            offers: <DeliveryOrder>[_order('o1', AssignmentStatus.accepted)],
            hasActiveDelivery: false,
          ),
          isFalse,
        );
      },
    );

    test('false when tied up with an active delivery, even if an assigned '
        'offer is somehow also present (R9.4 parity with the offer sheet)', () {
      expect(
        shouldPlayIncomingOrderAlert(
          offers: <DeliveryOrder>[_order('o1', AssignmentStatus.assigned)],
          hasActiveDelivery: true,
        ),
        isFalse,
      );
    });

    test('true when at least one of several offers is still pending', () {
      expect(
        shouldPlayIncomingOrderAlert(
          offers: <DeliveryOrder>[
            _order('o1', AssignmentStatus.accepted),
            _order('o2', AssignmentStatus.assigned),
          ],
          hasActiveDelivery: false,
        ),
        isTrue,
      );
    });

    test('false once every offer has resolved (declined/expired/taken — '
        'all removed from the list by OffersController)', () {
      expect(
        shouldPlayIncomingOrderAlert(
          offers: const <DeliveryOrder>[],
          hasActiveDelivery: false,
        ),
        isFalse,
      );
    });
  });
}
