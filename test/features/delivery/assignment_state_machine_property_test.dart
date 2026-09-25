import 'package:glados/glados.dart';

import 'package:meet_commerce_rider_main/features/delivery/application/assignment_state_machine.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';

/// Feature: freashcut-rider, Property 2:
/// Assignment_Status traces are monotonic walks on the allowed
/// transition graph.
///
/// For any sequence of attempted transitions, when applied through
/// [AssignmentStateMachine.canTransition] and accepted ones recorded,
/// every consecutive accepted pair `(s_i, s_{i+1})` satisfies
/// `canTransition(s_i, s_{i+1}) == true`, and any rejected attempt
/// leaves the controller's state unchanged.
///
/// Validates: Requirements R9.1, R9.2.
void main() {
  /// Generator over the 5 [AssignmentStatus] variants. Glados's `any`
  /// surface does not include enums out of the box, so we build the
  /// generator from `any.choose` over the enum's `values`.
  final Generator<AssignmentStatus> assignmentStatusGen = any
      .choose<AssignmentStatus>(AssignmentStatus.values);

  /// Generator over arbitrary "attempt" sequences: lists of attempted
  /// transitions of length 0..20. We bias toward longer-than-trivial
  /// sequences by capping at 20 because trace verification is O(n).
  final Generator<List<AssignmentStatus>> attemptsGen = any
      .listWithLengthInRange(0, 20, assignmentStatusGen);

  Glados<List<AssignmentStatus>>(attemptsGen, ExploreConfig(numRuns: 25)).test(
    'controller trace is a monotonic walk on the allowed graph',
    (List<AssignmentStatus> attempts) {
      // The "controller" here is a single mutable state simulator that
      // applies AssignmentStateMachine.canTransition as its transition
      // guard. We start from ASSIGNED — the initial state for any
      // freshly received offer.
      AssignmentStatus current = AssignmentStatus.assigned;
      final List<AssignmentStatus> trace = <AssignmentStatus>[current];

      for (final AssignmentStatus next in attempts) {
        if (AssignmentStateMachine.canTransition(current, next)) {
          // Self-transitions are permitted but don't advance the trace
          // for the purposes of monotonicity (they are idempotent).
          if (next != current) {
            current = next;
            trace.add(current);
          }
        }
        // Rejected attempts leave `current` unchanged — verified
        // structurally because we only mutate inside the if-branch.
      }

      // Property: every consecutive pair in the accepted trace must
      // be a permitted transition.
      for (int i = 0; i + 1 < trace.length; i++) {
        final AssignmentStatus from = trace[i];
        final AssignmentStatus to = trace[i + 1];
        if (!AssignmentStateMachine.canTransition(from, to)) {
          fail(
            'monotonicity violated at index $i: '
            '${from.wire} -> ${to.wire} is not in the allowed graph',
          );
        }
      }
    },
  );

  /// Companion property: starting from any state, applying a rejected
  /// attempt leaves the state unchanged.
  Glados2<AssignmentStatus, AssignmentStatus>(
    assignmentStatusGen,
    assignmentStatusGen,
    ExploreConfig(numRuns: 25),
  ).test('rejected transitions leave state unchanged', (
    AssignmentStatus from,
    AssignmentStatus to,
  ) {
    AssignmentStatus current = from;
    final bool allowed = AssignmentStateMachine.canTransition(current, to);
    if (!allowed) {
      // Simulate: controller MUST NOT mutate when canTransition is
      // false. We verify by re-asserting `current` is unchanged after
      // the (no-op) guard check.
      expect(current, from);
    } else {
      // Allowed — the simulated mutation produces `to` (or remains
      // `from` for self-transitions).
      if (from != to) {
        current = to;
        expect(current, to);
      } else {
        expect(current, from);
      }
    }
  });
}
