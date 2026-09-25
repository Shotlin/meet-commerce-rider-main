import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/features/delivery/application/assignment_state_machine.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/order_parse_exception.dart';

/// Standard (non-property) unit tests for [AssignmentStateMachine].
///
/// We tabulate every `(from, to)` pair to make the allowed graph obvious
/// from the test alone, then check the terminal-state and self-transition
/// guarantees explicitly.
void main() {
  group('AssignmentStateMachine.canTransition', () {
    final List<(AssignmentStatus, AssignmentStatus)> allowed =
        <(AssignmentStatus, AssignmentStatus)>[
          (AssignmentStatus.assigned, AssignmentStatus.accepted),
          (AssignmentStatus.assigned, AssignmentStatus.cancelled),
          (AssignmentStatus.accepted, AssignmentStatus.inTransit),
          (AssignmentStatus.accepted, AssignmentStatus.cancelled),
          (AssignmentStatus.inTransit, AssignmentStatus.delivered),
          (AssignmentStatus.inTransit, AssignmentStatus.cancelled),
        ];

    test('every documented edge is permitted', () {
      for (final (AssignmentStatus from, AssignmentStatus to) in allowed) {
        expect(
          AssignmentStateMachine.canTransition(from, to),
          isTrue,
          reason: '${from.wire} -> ${to.wire} should be allowed',
        );
      }
    });

    test('every undocumented edge is rejected', () {
      for (final AssignmentStatus from in AssignmentStatus.values) {
        for (final AssignmentStatus to in AssignmentStatus.values) {
          if (from == to) continue;
          final bool isAllowed = allowed.contains((from, to));
          expect(
            AssignmentStateMachine.canTransition(from, to),
            isAllowed,
            reason:
                '${from.wire} -> ${to.wire} should be '
                '${isAllowed ? 'allowed' : 'rejected'}',
          );
        }
      }
    });

    test('self-transition is permitted for every variant', () {
      for (final AssignmentStatus s in AssignmentStatus.values) {
        expect(AssignmentStateMachine.canTransition(s, s), isTrue);
      }
    });

    test('terminal states have no outgoing edges (other than self)', () {
      for (final AssignmentStatus terminal in <AssignmentStatus>[
        AssignmentStatus.delivered,
        AssignmentStatus.cancelled,
      ]) {
        for (final AssignmentStatus to in AssignmentStatus.values) {
          if (to == terminal) continue;
          expect(
            AssignmentStateMachine.canTransition(terminal, to),
            isFalse,
            reason: 'terminal ${terminal.wire} -> ${to.wire} must be rejected',
          );
        }
      }
    });
  });

  group('AssignmentStateMachine.isTerminal', () {
    test('delivered and cancelled are terminal', () {
      expect(
        AssignmentStateMachine.isTerminal(AssignmentStatus.delivered),
        isTrue,
      );
      expect(
        AssignmentStateMachine.isTerminal(AssignmentStatus.cancelled),
        isTrue,
      );
    });

    test('non-terminal states are not terminal', () {
      expect(
        AssignmentStateMachine.isTerminal(AssignmentStatus.assigned),
        isFalse,
      );
      expect(
        AssignmentStateMachine.isTerminal(AssignmentStatus.accepted),
        isFalse,
      );
      expect(
        AssignmentStateMachine.isTerminal(AssignmentStatus.inTransit),
        isFalse,
      );
    });
  });

  group('AssignmentStateMachine.reachableFrom', () {
    test('returns the configured edge set', () {
      expect(
        AssignmentStateMachine.reachableFrom(AssignmentStatus.assigned),
        equals(<AssignmentStatus>{
          AssignmentStatus.accepted,
          AssignmentStatus.cancelled,
        }),
      );
      expect(
        AssignmentStateMachine.reachableFrom(AssignmentStatus.delivered),
        isEmpty,
      );
    });
  });

  group('AssignmentStatus.parse', () {
    test('round-trips wire/parse for every variant', () {
      for (final AssignmentStatus s in AssignmentStatus.values) {
        expect(AssignmentStatus.parse(s.wire), s);
      }
    });

    test('accepts case and whitespace variants', () {
      expect(AssignmentStatus.parse('assigned'), AssignmentStatus.assigned);
      expect(
        AssignmentStatus.parse(' In_Transit '),
        AssignmentStatus.inTransit,
      );
      expect(AssignmentStatus.parse('CANCELED'), AssignmentStatus.cancelled);
    });

    test('throws for unknown values', () {
      expect(
        () => AssignmentStatus.parse('UNKNOWN'),
        throwsA(isA<UnknownAssignmentStatusException>()),
      );
    });
  });
}
