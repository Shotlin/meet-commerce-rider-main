import 'dart:developer' as developer;

import '../domain/assignment_status.dart';

/// Pure-Dart guard enforcing the allowed `AssignmentStatus` transition
/// graph from R9.
///
/// The graph (mirrors design.md):
///
/// ```
/// ASSIGNED   -> ACCEPTED, CANCELLED
/// ACCEPTED   -> IN_TRANSIT, CANCELLED
/// IN_TRANSIT -> DELIVERED, CANCELLED
/// DELIVERED  -> (terminal)
/// CANCELLED  -> (terminal)
/// ```
///
/// Self-transitions (`s -> s`) are allowed so the controller can apply
/// an idempotent re-emit (e.g. when the same socket event arrives twice
/// after a reconnection) without throwing.
///
/// Property 2 (R9.2): for any sequence of attempted transitions, the
/// controller's accepted trace is a monotonic walk on this graph.
/// `AssignmentStateMachine.canTransition` is the executable form of that
/// guard; `assignment_state_machine_property_test.dart` (Task 7.1)
/// verifies the property over arbitrary event sequences via `glados`.
abstract final class AssignmentStateMachine {
  /// Outgoing edges per source state.
  ///
  /// `const` so the table is fully tree-shaken on AOT builds.
  static const Map<AssignmentStatus, Set<AssignmentStatus>> allowed =
      <AssignmentStatus, Set<AssignmentStatus>>{
        AssignmentStatus.assigned: <AssignmentStatus>{
          AssignmentStatus.accepted,
          AssignmentStatus.cancelled,
        },
        AssignmentStatus.accepted: <AssignmentStatus>{
          AssignmentStatus.inTransit,
          AssignmentStatus.cancelled,
        },
        AssignmentStatus.inTransit: <AssignmentStatus>{
          AssignmentStatus.delivered,
          AssignmentStatus.cancelled,
        },
        AssignmentStatus.delivered: <AssignmentStatus>{},
        AssignmentStatus.cancelled: <AssignmentStatus>{},
      };

  /// Returns `true` iff the transition `from -> to` is permitted by the
  /// allowed graph. Self-transitions are always permitted.
  static bool canTransition(AssignmentStatus from, AssignmentStatus to) {
    if (identical(from, to) || from == to) return true;
    final Set<AssignmentStatus>? edges = allowed[from];
    if (edges == null) return false;
    return edges.contains(to);
  }

  /// Returns the set of states reachable from [from] in one step (not
  /// including [from] itself).
  ///
  /// Useful for diagnostics and UI hints (e.g., "you can still cancel
  /// from ACCEPTED").
  static Set<AssignmentStatus> reachableFrom(AssignmentStatus from) {
    return allowed[from] ?? const <AssignmentStatus>{};
  }

  /// Whether [s] is a terminal state (no outgoing transitions).
  static bool isTerminal(AssignmentStatus s) =>
      s == AssignmentStatus.delivered || s == AssignmentStatus.cancelled;

  /// Convenience: returns `next` when the transition `current -> next`
  /// is allowed, otherwise returns `current` (rejecting the transition)
  /// and logs a warning with [orderId].
  ///
  /// Used by `OffersController` and `ActiveDeliveryController` so the
  /// monotonic-walk invariant is enforced at every state mutation site
  /// without each caller reimplementing the guard.
  static AssignmentStatus apply(
    AssignmentStatus current,
    AssignmentStatus next, {
    String? orderId,
  }) {
    if (canTransition(current, next)) return next;
    developer.log(
      'Illegal transition rejected: ${current.wire} -> ${next.wire}'
      '${orderId != null ? ' for order $orderId' : ''}',
      name: 'STATE',
      level: 900, // WARN
    );
    return current;
  }
}
