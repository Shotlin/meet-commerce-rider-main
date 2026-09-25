import 'package:flutter/foundation.dart';

/// Sealed result type returned by the delivery action sheets
/// (`showProofUploadSheet`, `showDemoCompleteSheet`; pickup verification lives in the QR scan → checklist flow, not a sheet).
///
/// Pattern matching:
/// ```
/// switch (outcome) {
///   case DeliveryOutcomeDelivered(:final orderId, :final earnedAmount, :final totalToday):
///     // open completion summary
///   case DeliveryOutcomeCancelled():
///     // rider dismissed the sheet
///   case DeliveryOutcomeFailed(:final message):
///     // surface the message
/// }
/// ```
///
/// The presentation layer uses this surface to decide whether to chain
/// into the completion summary sheet or surface a snackbar; the
/// underlying state-machine result type ([DeliveryResult]) stays an
/// implementation detail of the controller.
@immutable
sealed class DeliveryOutcome {
  /// Const constructor.
  const DeliveryOutcome();
}

/// The delivery completed successfully. Carries enough information
/// for the completion summary sheet to render without re-fetching.
@immutable
final class DeliveryOutcomeDelivered extends DeliveryOutcome {
  /// Constructs a successful outcome.
  const DeliveryOutcomeDelivered({
    required this.orderId,
    required this.earnedAmount,
    required this.totalToday,
  });

  /// Order identifier of the just-completed delivery.
  final String orderId;

  /// Earnings credited to the rider for this delivery.
  final double earnedAmount;

  /// Rider's total earnings for the current day, post-credit.
  final double totalToday;
}

/// The rider dismissed the sheet without completing the action.
@immutable
final class DeliveryOutcomeCancelled extends DeliveryOutcome {
  /// Const constructor.
  const DeliveryOutcomeCancelled();
}

/// The action failed (network, validation, conflict). The [message]
/// is the user-facing copy already translated by the controller.
@immutable
final class DeliveryOutcomeFailed extends DeliveryOutcome {
  /// Constructs a failed outcome.
  const DeliveryOutcomeFailed(this.message);

  /// User-facing copy.
  final String message;
}
