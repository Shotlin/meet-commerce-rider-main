import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/order_parse_exception.dart';

/// Minimal valid order JSON for use in tests.
Map<String, dynamic> _validOrderJson({
  String orderId = 'order-123',
  String assignmentStatus = 'ASSIGNED',
}) => <String, dynamic>{
  'orderId': orderId,
  'assignmentId': 'assign-456',
  'orderNumber': 'ORD-001',
  'assignmentStatus': assignmentStatus,
  'orderStatus': 'CONFIRMED',
  'totalAmount': 250.50,
  'paymentMethod': 'ONLINE',
  'riderEarning': 35.00,
  'estimatedDistance': 3.5,
  'estimatedDuration': 20,
  'customerAddress': <String, dynamic>{
    'name': 'Priya Nair',
    'address': '12 Lake View',
    'landmark': 'Near lake',
    'phone': '9999999999',
    'lat': 22.5726,
    'lng': 88.3639,
  },
  'storeAddress': <String, dynamic>{
    'name': 'FreshCuts Store',
    'address': 'Hub 1',
    'lat': 22.5800,
    'lng': 88.3700,
  },
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'item-1',
      'name': 'Milk',
      'quantity': 2,
      'unitPrice': 50.00,
      'totalPrice': 100.00,
    },
  ],
};

void main() {
  group('DeliveryOrder.fromJson', () {
    test('parses a valid camelCase order', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(_validOrderJson());

      expect(order.orderId, 'order-123');
      expect(order.assignmentId, 'assign-456');
      expect(order.orderNumber, 'ORD-001');
      expect(order.assignmentStatus, AssignmentStatus.assigned);
      expect(order.orderStatus, 'CONFIRMED');
      expect(order.totalAmount, closeTo(250.50, 0.001));
      expect(order.paymentMethod, 'ONLINE');
      expect(order.riderEarning, closeTo(35.00, 0.001));
      expect(order.estimatedDistance, closeTo(3.5, 0.001));
      expect(order.estimatedDuration, 20);
      expect(order.customerAddress.name, 'Priya Nair');
      expect(order.storeAddress.name, 'FreshCuts Store');
      expect(order.items.length, 1);
      expect(order.items.first.name, 'Milk');
    });

    test('accepts snake_case field names', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        'order_id': 'order-snake',
        'assignment_id': 'assign-snake',
        'order_number': 'ORD-SNAKE',
        'assignment_status': 'ACCEPTED',
        'total_amount': '150.75',
        'payment_method': 'COD',
        'rider_earning': '20.00',
        'estimated_distance': '2.5',
        'estimated_duration': 15,
        'customer_address': <String, dynamic>{
          'name': 'Customer',
          'address': 'Addr',
          'lat': 22.5726,
          'lng': 88.3639,
        },
        'store_address': <String, dynamic>{
          'name': 'Store',
          'address': 'Hub',
          'lat': 22.58,
          'lng': 88.37,
        },
        'items': <dynamic>[],
      });

      expect(order.orderId, 'order-snake');
      expect(order.assignmentId, 'assign-snake');
      expect(order.orderNumber, 'ORD-SNAKE');
      expect(order.assignmentStatus, AssignmentStatus.accepted);
      expect(order.totalAmount, closeTo(150.75, 0.001));
      expect(order.riderEarning, closeTo(20.00, 0.001));
      expect(order.estimatedDistance, closeTo(2.5, 0.001));
    });

    test('prefers camelCase over snake_case when both present', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        'orderId': 'camel-id',
        'order_id': 'snake-id',
        'assignmentStatus': 'ASSIGNED',
        'assignment_status': 'DELIVERED',
        'totalAmount': 100.0,
        'total_amount': 999.0,
        'riderEarning': 10.0,
        'rider_earning': 99.0,
        'paymentMethod': 'ONLINE',
        'estimatedDuration': 10,
        'customerAddress': <String, dynamic>{'name': 'C', 'address': 'A'},
        'storeAddress': <String, dynamic>{'name': 'S', 'address': 'B'},
        'items': <dynamic>[],
      });

      expect(order.orderId, 'camel-id');
      expect(order.assignmentStatus, AssignmentStatus.assigned);
      expect(order.totalAmount, closeTo(100.0, 0.001));
      expect(order.riderEarning, closeTo(10.0, 0.001));
    });

    test('parses money fields from string values', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        'orderId': 'order-str',
        'assignmentStatus': 'ASSIGNED',
        'totalAmount': '250.50',
        'riderEarning': '35.00',
        'paymentMethod': 'ONLINE',
        'estimatedDuration': 20,
        'customerAddress': <String, dynamic>{'name': 'C', 'address': 'A'},
        'storeAddress': <String, dynamic>{'name': 'S', 'address': 'B'},
        'items': <dynamic>[],
      });

      expect(order.totalAmount, closeTo(250.50, 0.001));
      expect(order.riderEarning, closeTo(35.00, 0.001));
    });

    test('rounds money to 2 decimal places', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        'orderId': 'order-round',
        'assignmentStatus': 'ASSIGNED',
        'totalAmount': 100.999,
        'riderEarning': 10.005,
        'paymentMethod': 'ONLINE',
        'estimatedDuration': 10,
        'customerAddress': <String, dynamic>{'name': 'C', 'address': 'A'},
        'storeAddress': <String, dynamic>{'name': 'S', 'address': 'B'},
        'items': <dynamic>[],
      });

      // (100.999 * 100).round() / 100 = 101.0
      expect(order.totalAmount, closeTo(101.0, 0.001));
    });
  });

  group('DeliveryOrder round-trip (R19.3)', () {
    test('fromJson(toJson(order)) == order', () {
      final DeliveryOrder original = DeliveryOrder.fromJson(_validOrderJson());
      final DeliveryOrder roundTripped = DeliveryOrder.fromJson(
        original.toJson(),
      );

      expect(roundTripped, equals(original));
    });

    test('round-trip preserves all assignment statuses', () {
      for (final AssignmentStatus status in AssignmentStatus.values) {
        final DeliveryOrder original = DeliveryOrder.fromJson(
          _validOrderJson(assignmentStatus: status.wire),
        );
        final DeliveryOrder roundTripped = DeliveryOrder.fromJson(
          original.toJson(),
        );
        expect(roundTripped.assignmentStatus, status);
      }
    });

    test('round-trip with items preserves item data', () {
      final DeliveryOrder original = DeliveryOrder.fromJson(<String, dynamic>{
        'orderId': 'order-items',
        'assignmentStatus': 'ASSIGNED',
        'totalAmount': 300.0,
        'riderEarning': 40.0,
        'paymentMethod': 'ONLINE',
        'estimatedDuration': 25,
        'customerAddress': <String, dynamic>{'name': 'C', 'address': 'A'},
        'storeAddress': <String, dynamic>{'name': 'S', 'address': 'B'},
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'i1',
            'name': 'Bread',
            'quantity': 1,
            'unitPrice': 30.0,
            'totalPrice': 30.0,
          },
          <String, dynamic>{
            'id': 'i2',
            'name': 'Butter',
            'quantity': 2,
            'unitPrice': 50.0,
            'totalPrice': 100.0,
          },
        ],
      });

      final DeliveryOrder roundTripped = DeliveryOrder.fromJson(
        original.toJson(),
      );

      expect(roundTripped.items.length, 2);
      expect(roundTripped.items[0].name, 'Bread');
      expect(roundTripped.items[1].name, 'Butter');
      expect(roundTripped, equals(original));
    });
  });

  group('DeliveryOrder error cases', () {
    test('throws OrderParseException when orderId is missing (R19.4)', () {
      expect(
        () => DeliveryOrder.fromJson(<String, dynamic>{
          'assignmentStatus': 'ASSIGNED',
          'totalAmount': 100.0,
          'riderEarning': 10.0,
          'paymentMethod': 'ONLINE',
          'estimatedDuration': 10,
          'customerAddress': <String, dynamic>{'name': 'C', 'address': 'A'},
          'storeAddress': <String, dynamic>{'name': 'S', 'address': 'B'},
          'items': <dynamic>[],
        }),
        throwsA(isA<OrderParseException>()),
      );
    });

    test(
      'throws OrderParseException when assignmentStatus is missing (R19.4)',
      () {
        expect(
          () => DeliveryOrder.fromJson(<String, dynamic>{
            'orderId': 'order-123',
            'totalAmount': 100.0,
            'riderEarning': 10.0,
            'paymentMethod': 'ONLINE',
            'estimatedDuration': 10,
            'customerAddress': <String, dynamic>{'name': 'C', 'address': 'A'},
            'storeAddress': <String, dynamic>{'name': 'S', 'address': 'B'},
            'items': <dynamic>[],
          }),
          throwsA(isA<OrderParseException>()),
        );
      },
    );

    test(
      'throws UnknownAssignmentStatusException for unknown status (R19.5)',
      () {
        expect(
          () => DeliveryOrder.fromJson(<String, dynamic>{
            'orderId': 'order-123',
            'assignmentStatus': 'FLYING',
            'totalAmount': 100.0,
            'riderEarning': 10.0,
            'paymentMethod': 'ONLINE',
            'estimatedDuration': 10,
            'customerAddress': <String, dynamic>{'name': 'C', 'address': 'A'},
            'storeAddress': <String, dynamic>{'name': 'S', 'address': 'B'},
            'items': <dynamic>[],
          }),
          throwsA(isA<UnknownAssignmentStatusException>()),
        );
      },
    );

    test('throws OrderParseException when customerAddress is missing', () {
      expect(
        () => DeliveryOrder.fromJson(<String, dynamic>{
          'orderId': 'order-123',
          'assignmentStatus': 'ASSIGNED',
          'totalAmount': 100.0,
          'riderEarning': 10.0,
          'paymentMethod': 'ONLINE',
          'estimatedDuration': 10,
          'storeAddress': <String, dynamic>{'name': 'S', 'address': 'B'},
          'items': <dynamic>[],
        }),
        throwsA(isA<OrderParseException>()),
      );
    });
  });

  group('AssignmentStatus.parse', () {
    test('parses all known statuses', () {
      expect(AssignmentStatus.parse('ASSIGNED'), AssignmentStatus.assigned);
      expect(AssignmentStatus.parse('ACCEPTED'), AssignmentStatus.accepted);
      expect(AssignmentStatus.parse('IN_TRANSIT'), AssignmentStatus.inTransit);
      expect(AssignmentStatus.parse('DELIVERED'), AssignmentStatus.delivered);
      expect(AssignmentStatus.parse('CANCELLED'), AssignmentStatus.cancelled);
    });

    test('is case-insensitive', () {
      expect(AssignmentStatus.parse('assigned'), AssignmentStatus.assigned);
      expect(AssignmentStatus.parse('Accepted'), AssignmentStatus.accepted);
    });

    test('throws UnknownAssignmentStatusException for unknown value', () {
      expect(
        () => AssignmentStatus.parse('UNKNOWN_STATUS'),
        throwsA(isA<UnknownAssignmentStatusException>()),
      );
    });

    test('wire getter returns correct backend strings', () {
      expect(AssignmentStatus.assigned.wire, 'ASSIGNED');
      expect(AssignmentStatus.accepted.wire, 'ACCEPTED');
      expect(AssignmentStatus.inTransit.wire, 'IN_TRANSIT');
      expect(AssignmentStatus.delivered.wire, 'DELIVERED');
      expect(AssignmentStatus.cancelled.wire, 'CANCELLED');
    });
  });

  group('DeliveryOrder.copyWith', () {
    test('copyWith replaces only specified fields', () {
      final DeliveryOrder original = DeliveryOrder.fromJson(_validOrderJson());
      final DeliveryOrder updated = original.copyWith(
        assignmentStatus: AssignmentStatus.accepted,
        riderEarning: 50.0,
      );

      expect(updated.assignmentStatus, AssignmentStatus.accepted);
      expect(updated.riderEarning, closeTo(50.0, 0.001));
      expect(updated.orderId, original.orderId);
      expect(updated.totalAmount, original.totalAmount);
    });
  });

  group(
    'DeliveryOrder.compareDeliveryPriority (item 8/9: multi-stop sequencing)',
    () {
      final DeliveryOrder base = DeliveryOrder.fromJson(_validOrderJson());

      DeliveryOrder order({
        bool quickDelivery = false,
        DateTime? scheduledSlotStart,
        DateTime? createdAt,
      }) {
        return base.copyWith(
          quickDeliverySelected: quickDelivery,
          scheduledSlotStart: scheduledSlotStart,
          createdAt: createdAt,
        );
      }

      test(
        'an Express (quick delivery) order always sorts before a non-Express order',
        () {
          final DeliveryOrder express = order(
            quickDelivery: true,
            createdAt: DateTime(2026, 8, 15, 12), // placed later
          );
          final DeliveryOrder standard = order(
            createdAt: DateTime(
              2026,
              8,
              15,
              9,
            ), // placed earlier — would win on time alone
          );

          final List<DeliveryOrder> sorted = <DeliveryOrder>[standard, express]
            ..sort(DeliveryOrder.compareDeliveryPriority);

          expect(sorted.first, express);
        },
      );

      test(
        'within the same tier, the earlier placed (createdAt) ASAP order goes first',
        () {
          final DeliveryOrder later = order(
            createdAt: DateTime(2026, 8, 15, 12),
          );
          final DeliveryOrder earlier = order(
            createdAt: DateTime(2026, 8, 15, 9),
          );

          final List<DeliveryOrder> sorted = <DeliveryOrder>[later, earlier]
            ..sort(DeliveryOrder.compareDeliveryPriority);

          expect(sorted.first, earlier);
        },
      );

      test(
        'a scheduled order sequences by its promised slot start, not createdAt',
        () {
          final DeliveryOrder placedFirstSlotLater = order(
            createdAt: DateTime(2026, 8, 15, 8),
            scheduledSlotStart: DateTime(2026, 8, 15, 18), // 6 PM window
          );
          final DeliveryOrder placedLaterSlotSooner = order(
            createdAt: DateTime(2026, 8, 15, 10),
            scheduledSlotStart: DateTime(2026, 8, 15, 14), // 2 PM window
          );

          final List<DeliveryOrder> sorted = <DeliveryOrder>[
            placedFirstSlotLater,
            placedLaterSlotSooner,
          ]..sort(DeliveryOrder.compareDeliveryPriority);

          // The 2 PM window comes before the 6 PM window regardless of which
          // order was placed (created) first.
          expect(sorted.first, placedLaterSlotSooner);
        },
      );

      test(
        'multiple Express orders are still ranked among themselves by time',
        () {
          final DeliveryOrder expressLater = order(
            quickDelivery: true,
            createdAt: DateTime(2026, 8, 15, 12),
          );
          final DeliveryOrder expressEarlier = order(
            quickDelivery: true,
            createdAt: DateTime(2026, 8, 15, 9),
          );
          final DeliveryOrder standard = order(
            createdAt: DateTime(2026, 8, 15, 1),
          );

          final List<DeliveryOrder> sorted = <DeliveryOrder>[
            standard,
            expressLater,
            expressEarlier,
          ]..sort(DeliveryOrder.compareDeliveryPriority);

          expect(sorted, <DeliveryOrder>[
            expressEarlier,
            expressLater,
            standard,
          ]);
        },
      );

      test(
        'orders with no timestamp at all sort after ones that have one, within the same tier',
        () {
          final DeliveryOrder noTimestamp = order();
          final DeliveryOrder withTimestamp = order(
            createdAt: DateTime(2026, 8, 15, 9),
          );

          final List<DeliveryOrder> sorted = <DeliveryOrder>[
            noTimestamp,
            withTimestamp,
          ]..sort(DeliveryOrder.compareDeliveryPriority);

          expect(sorted.first, withTimestamp);
        },
      );
    },
  );

  group('DeliveryOrder.distanceFromMeters', () {
    final DeliveryOrder base = DeliveryOrder.fromJson(_validOrderJson());

    test('computes a positive haversine distance to the customer address', () {
      final DeliveryOrder farAway = base.copyWith(
        customerAddress: DeliveryAddress(
          name: 'Customer',
          address: 'Far away',
          lat: 23.5726, // ~1 degree of latitude away
          lng: 88.3639,
        ),
      );

      final double? distance = farAway.distanceFromMeters(
        const GeoPoint(22.5726, 88.3639),
      );

      expect(distance, isNotNull);
      expect(distance, greaterThan(100000)); // roughly 111 km per degree
    });

    test('returns null when the customer address has no coordinates', () {
      final DeliveryOrder noCoords = base.copyWith(
        customerAddress: DeliveryAddress(
          name: 'Customer',
          address: 'Somewhere',
        ),
      );

      expect(
        noCoords.distanceFromMeters(const GeoPoint(22.5726, 88.3639)),
        isNull,
      );
    });
  });
}
