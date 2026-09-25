import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/order_parse_exception.dart';

void main() {
  group('AssignmentStatus.parse', () {
    // -------------------------------------------------------------------------
    // Uppercase wire form (canonical)
    // -------------------------------------------------------------------------
    group('accepts canonical uppercase', () {
      const Map<String, AssignmentStatus> cases = <String, AssignmentStatus>{
        'ASSIGNED': AssignmentStatus.assigned,
        'ACCEPTED': AssignmentStatus.accepted,
        'IN_TRANSIT': AssignmentStatus.inTransit,
        'DELIVERED': AssignmentStatus.delivered,
        'CANCELLED': AssignmentStatus.cancelled,
      };

      cases.forEach((String wire, AssignmentStatus expected) {
        test('"$wire" → $expected', () {
          expect(AssignmentStatus.parse(wire), expected);
        });
      });
    });

    // -------------------------------------------------------------------------
    // Lowercase form
    // -------------------------------------------------------------------------
    group('accepts lowercase', () {
      const Map<String, AssignmentStatus> cases = <String, AssignmentStatus>{
        'assigned': AssignmentStatus.assigned,
        'accepted': AssignmentStatus.accepted,
        'in_transit': AssignmentStatus.inTransit,
        'delivered': AssignmentStatus.delivered,
        'cancelled': AssignmentStatus.cancelled,
      };

      cases.forEach((String wire, AssignmentStatus expected) {
        test('"$wire" → $expected', () {
          expect(AssignmentStatus.parse(wire), expected);
        });
      });
    });

    // -------------------------------------------------------------------------
    // Mixed case
    // -------------------------------------------------------------------------
    group('accepts mixed case', () {
      const Map<String, AssignmentStatus> cases = <String, AssignmentStatus>{
        'Assigned': AssignmentStatus.assigned,
        'aCcEpTeD': AssignmentStatus.accepted,
        'In_Transit': AssignmentStatus.inTransit,
        'Delivered': AssignmentStatus.delivered,
        'cAnCeLlEd': AssignmentStatus.cancelled,
      };

      cases.forEach((String wire, AssignmentStatus expected) {
        test('"$wire" → $expected', () {
          expect(AssignmentStatus.parse(wire), expected);
        });
      });
    });

    // -------------------------------------------------------------------------
    // Unknown values throw the typed exception (R19.5)
    // -------------------------------------------------------------------------
    group('throws UnknownAssignmentStatusException for unknown values', () {
      const List<String> unknowns = <String>[
        'UNKNOWN',
        '',
        'PICKED_UP',
        'IN-TRANSIT',
        'DELIVRED',
        'in transit',
        'pending',
      ];

      for (final String value in unknowns) {
        test('rejects "$value"', () {
          expect(
            () => AssignmentStatus.parse(value),
            throwsA(isA<UnknownAssignmentStatusException>()),
          );
        });
      }

      test('exception captures the offending wire value', () {
        try {
          AssignmentStatus.parse('NOPE');
          fail('expected UnknownAssignmentStatusException');
        } on UnknownAssignmentStatusException catch (e) {
          expect(e.value, 'NOPE');
          expect(e.toString(), contains('NOPE'));
        }
      });
    });
  });

  // ---------------------------------------------------------------------------
  // wire getter
  // ---------------------------------------------------------------------------
  group('AssignmentStatus.wire', () {
    test('returns canonical uppercase wire strings', () {
      expect(AssignmentStatus.assigned.wire, 'ASSIGNED');
      expect(AssignmentStatus.accepted.wire, 'ACCEPTED');
      expect(AssignmentStatus.inTransit.wire, 'IN_TRANSIT');
      expect(AssignmentStatus.delivered.wire, 'DELIVERED');
      expect(AssignmentStatus.cancelled.wire, 'CANCELLED');
    });

    test('round-trips for every value: parse(wire) == value', () {
      for (final AssignmentStatus value in AssignmentStatus.values) {
        expect(
          AssignmentStatus.parse(value.wire),
          value,
          reason: 'parse(${value.wire}) should equal $value',
        );
      }
    });

    test('round-trips through lowercase too', () {
      for (final AssignmentStatus value in AssignmentStatus.values) {
        expect(
          AssignmentStatus.parse(value.wire.toLowerCase()),
          value,
          reason: 'parse(${value.wire.toLowerCase()}) should equal $value',
        );
      }
    });
  });
}
