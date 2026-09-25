import 'order_parse_exception.dart';

/// Lifecycle status of a delivery assignment.
///
/// The state machine that governs allowed transitions lives in
/// `AssignmentStateMachine` (Task 7.1). This enum is the wire-level
/// representation; serialization to/from the backend's `ASSIGNED`,
/// `ACCEPTED`, `IN_TRANSIT`, `DELIVERED`, `CANCELLED` strings goes
/// through [AssignmentStatus.parse] / `wire`.
///
/// Property 2 (R9): the sequence of `AssignmentStatus` values applied to
/// a single assignment is a monotonic walk on the allowed-transition
/// graph. Unknown wire values throw [UnknownAssignmentStatusException]
/// rather than silently degrade so that bug never enters the
/// controller's accepted history.
enum AssignmentStatus {
  /// Offer presented to the rider; awaiting accept/reject.
  assigned,

  /// Rider accepted; navigating to the store.
  accepted,

  /// Rider picked up from the store; navigating to the customer.
  inTransit,

  /// Delivery completed successfully (terminal).
  delivered,

  /// Order rejected, expired, or otherwise unavailable (terminal).
  cancelled;

  /// Wire-level (backend) representation.
  String get wire {
    switch (this) {
      case AssignmentStatus.assigned:
        return 'ASSIGNED';
      case AssignmentStatus.accepted:
        return 'ACCEPTED';
      case AssignmentStatus.inTransit:
        return 'IN_TRANSIT';
      case AssignmentStatus.delivered:
        return 'DELIVERED';
      case AssignmentStatus.cancelled:
        return 'CANCELLED';
    }
  }

  /// Whether this is a terminal state (no outgoing transitions allowed).
  bool get isTerminal =>
      this == AssignmentStatus.delivered || this == AssignmentStatus.cancelled;

  /// Parses a wire value into an [AssignmentStatus]. Accepts the
  /// canonical uppercase form and is case- and whitespace-tolerant.
  ///
  /// Throws [UnknownAssignmentStatusException] for any value the rider
  /// app does not recognize.
  static AssignmentStatus parse(String raw) {
    switch (raw.toUpperCase().trim()) {
      case 'ASSIGNED':
        return AssignmentStatus.assigned;
      case 'ACCEPTED':
        return AssignmentStatus.accepted;
      case 'IN_TRANSIT':
        return AssignmentStatus.inTransit;
      case 'DELIVERED':
        return AssignmentStatus.delivered;
      case 'CANCELLED':
      case 'CANCELED':
        return AssignmentStatus.cancelled;
      default:
        throw UnknownAssignmentStatusException(raw);
    }
  }
}

/// Backwards-compat alias kept for code that was written before
/// [AssignmentStatus.parse] became a member of the enum itself.
extension AssignmentStatusX on AssignmentStatus {
  /// Same as [AssignmentStatus.wire], retained for older import sites.
  String toWire() => wire;
}
