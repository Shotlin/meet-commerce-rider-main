import 'package:flutter/foundation.dart';

import 'location_lifecycle_manager.dart';
import 'location_profile.dart';
import '../../features/delivery/application/active_delivery_map_controller.dart';

/// Maps the delivery map's [LocationPhase] onto the rider's GPS
/// location profile (requirement §23) with change detection.
///
/// Phase 6 built the profile machinery
/// ([LocationLifecycleManager.onAcceptedOrder] / [onPickedUp] /
/// [onDeliveryEnded]); Phase 13 wires it to the delivery map screen's
/// order-application path so tracking frequency actually escalates:
///
/// - `toStore`    → [LocationProfile.acceptedToStore] (higher frequency)
/// - `toCustomer` → [LocationProfile.inTransitToCustomer] (highest)
/// - `none` after an active phase → [LocationProfile.waitingOnline]
///   (delivery ended; the rider returns to the waiting profile without
///   touching their dispatch-online flag)
///
/// The manager itself early-returns on an unchanged profile, but this
/// helper still tracks the last applied phase so callers only invoke
/// the lifecycle when something actually changed (and so a screen
/// rebuild never replays a terminal transition).
class DeliveryLocationPhaseSync {
  /// Constructs the sync helper.
  DeliveryLocationPhaseSync();

  LocationPhase? _lastPhase;

  /// The last phase this helper applied. Null before the first call.
  @visibleForTesting
  LocationPhase? get lastPhase => _lastPhase;

  /// Applies [phase] to [manager] if it differs from the last applied
  /// phase. Returns `true` when a lifecycle call was made.
  Future<bool> apply(
    LocationPhase phase,
    LocationLifecycleManager manager,
  ) async {
    if (_lastPhase == phase) return false;
    final LocationPhase? previous = _lastPhase;
    _lastPhase = phase;
    switch (phase) {
      case LocationPhase.toStore:
        await manager.onAcceptedOrder();
      case LocationPhase.toCustomer:
        await manager.onPickedUp();
      case LocationPhase.none:
        // `none` is also the initial state of a fresh screen — only
        // treat it as "delivery ended" when a real phase preceded it.
        if (previous != null) {
          await manager.onDeliveryEnded();
        }
    }
    return true;
  }

  /// Forgets the last phase (logout / screen dispose with session reset).
  void reset() => _lastPhase = null;
}
