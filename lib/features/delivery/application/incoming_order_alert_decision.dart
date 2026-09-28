import '../domain/assignment_status.dart';
import '../domain/delivery_order.dart';

/// Pure decision: should the incoming-order alarm (looping sound + strong
/// vibration) currently be playing?
///
/// True exactly when the rider has at least one offer still awaiting a
/// decision (`AssignmentStatus.assigned`) and is not already tied up with
/// an active delivery — the same suppression rule
/// [OffersController.hasActiveDelivery] already applies to the offer
/// bottom sheet (R9.4), so the alarm and the sheet never disagree about
/// whether a new offer is actually actionable right now.
///
/// Deliberately takes plain values rather than the whole
/// `OffersController` so it can be unit-tested with fixtures alone, and
/// so `IncomingOrderAlertListener` has one line of truth to call on every
/// controller change instead of re-deriving this logic inline.
bool shouldPlayIncomingOrderAlert({
  required List<DeliveryOrder> offers,
  required bool hasActiveDelivery,
}) {
  if (hasActiveDelivery) return false;
  return offers.any(
    (DeliveryOrder o) => o.assignmentStatus == AssignmentStatus.assigned,
  );
}
