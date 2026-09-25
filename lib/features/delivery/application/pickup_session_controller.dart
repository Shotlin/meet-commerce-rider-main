import 'package:flutter/foundation.dart';

import '../domain/assignment_status.dart';
import '../domain/delivery_order.dart';
import '../domain/pickup_session.dart';

/// Tracks QR-pickup progress for the rider's **single** active order —
/// purely client-side, session-local state layered on top of
/// [ActiveDeliveryController]. The backend has no notion of "needs scan"
/// vs. "verified": that's the `order_pickup_tokens` row's own
/// ACTIVE/VERIFIED/CONSUMED lifecycle, enforced server-side on every
/// `verify-scan`/`markPickedUp` call regardless of what this controller
/// thinks — this is a UI convenience so the scanner/checklist surfaces
/// can show where the rider is without re-querying token status on
/// every rebuild.
///
/// Statuses stay keyed by orderId (not a bare field) so a late event
/// for a *previous* order can never be misread as state for the current
/// one. Pure-Dart [ChangeNotifier], no Riverpod, matching every other
/// controller in this feature.
class PickupSessionController extends ChangeNotifier {
  final Map<String, PickupScanStatus> _status = <String, PickupScanStatus>{};
  final Map<String, PickupVerification> _verifications =
      <String, PickupVerification>{};

  /// Read-only snapshot of the tracked order's current scan status.
  Map<String, PickupScanStatus> get statuses =>
      Map<String, PickupScanStatus>.unmodifiable(_status);

  /// The checklist returned by `verify-scan` for [orderId], if it's been
  /// scanned this session.
  PickupVerification? verificationFor(String orderId) =>
      _verifications[orderId];

  PickupScanStatus statusFor(String orderId) =>
      _status[orderId] ?? PickupScanStatus.needsScan;

  /// Whether [orderId] has reached [PickupScanStatus.pickedUp] this
  /// session (pickup confirmed).
  bool isPickedUp(String orderId) =>
      statusFor(orderId) == PickupScanStatus.pickedUp;

  /// Ensures the active [order] has a tracked status, without clobbering
  /// an entry that's already further along (e.g. re-called after a
  /// routine `/delivery/orders` reconciliation). A new entry is seeded
  /// from the order's real wire status: still
  /// [AssignmentStatus.accepted] means it hasn't been picked up yet
  /// this app install, so it needs a scan; [AssignmentStatus.inTransit]
  /// means pickup already happened (e.g. the app was restarted
  /// mid-delivery) so there's nothing to scan this session.
  ///
  /// A `null` [order] (rider has no active delivery) is a no-op — the
  /// caller clears the session explicitly via [reset] when the whole
  /// flow ends.
  void syncFromOrder(DeliveryOrder? order) {
    if (order == null || _status.containsKey(order.orderId)) return;
    _status[order.orderId] =
        order.assignmentStatus == AssignmentStatus.inTransit
        ? PickupScanStatus.pickedUp
        : PickupScanStatus.needsScan;
    notifyListeners();
  }

  /// Records a successful `verify-scan` result for [orderId].
  void markVerified(String orderId, PickupVerification verification) {
    _status[orderId] = PickupScanStatus.verified;
    _verifications[orderId] = verification;
    notifyListeners();
  }

  /// Records a successful pickup confirmation (`markPickedUp` succeeded)
  /// for [orderId].
  void markPickedUp(String orderId) {
    _status[orderId] = PickupScanStatus.pickedUp;
    notifyListeners();
  }

  /// Drops [orderId] from this session (order cancelled/removed before
  /// pickup).
  void remove(String orderId) {
    if (_status.remove(orderId) == null) return;
    _verifications.remove(orderId);
    notifyListeners();
  }

  /// Clears the whole session — called once the rider leaves the pickup
  /// phase and moves into delivering, so a later store visit starts
  /// fresh.
  void reset() {
    _status.clear();
    _verifications.clear();
    notifyListeners();
  }
}
