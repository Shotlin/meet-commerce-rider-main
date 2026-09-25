import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../maps/geo_point.dart';
import '../realtime/socket_client.dart';
import '../../features/delivery/data/delivery_api.dart';
import 'location_permission_service.dart';
import 'location_permission_status.dart';
import 'location_profile.dart';
import 'location_service.dart';

/// Manages the full rider location lifecycle:
///
/// 1. Requests permission when needed.
/// 2. Starts / stops the GPS stream based on online state.
/// 3. Writes every GPS fix into [riderLocationNotifier] so the map
///    marker updates in real time on any screen.
/// 4. Uploads every fix to the backend via socket (primary) or REST
///    (fallback) — no manual `adb geo fix` needed.
///
/// Call [onWentOnline] when the rider goes online and [onWentOffline]
/// when they go offline. The manager handles everything else.
class LocationLifecycleManager {
  LocationLifecycleManager({
    required ValueNotifier<GeoPoint?> riderLocationNotifier,
    required LocationService locationService,
    required LocationPermissionService permissionService,
    required SocketClient socket,
    required DeliveryApi deliveryApi,
  }) : _notifier = riderLocationNotifier,
       _locationService = locationService,
       _permissionService = permissionService,
       _socket = socket,
       _deliveryApi = deliveryApi;

  final ValueNotifier<GeoPoint?> _notifier;
  final LocationService _locationService;
  final LocationPermissionService _permissionService;
  final SocketClient _socket;
  final DeliveryApi _deliveryApi;

  StreamSubscription<Position>? _subscription;
  LocationProfile _currentProfile = LocationProfile.offline;
  bool _isOnline = false;

  // Throttle: don't upload more than once every 5 seconds.
  DateTime? _lastUploadAt;
  static const Duration _minUploadInterval = Duration(seconds: 5);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Whether the GPS stream is currently active.
  bool get isStreaming => _subscription != null;

  /// Called when the rider taps "Go online". Requests permission if
  /// needed, then starts the GPS stream.
  Future<void> onWentOnline() async {
    _isOnline = true;
    await _ensurePermissionAndStart(LocationProfile.waitingOnline);
  }

  /// Called when the rider taps "Go offline". Stops the GPS stream.
  Future<void> onWentOffline() async {
    _isOnline = false;
    await _stop();
  }

  /// Called when the rider accepts an order (heading to store).
  Future<void> onAcceptedOrder() async {
    if (!_isOnline) return;
    await _switchProfile(LocationProfile.acceptedToStore);
  }

  /// Called when the rider picks up the order (heading to customer).
  Future<void> onPickedUp() async {
    if (!_isOnline) return;
    await _switchProfile(LocationProfile.inTransitToCustomer);
  }

  /// Called when a delivery completes or is cancelled.
  Future<void> onDeliveryEnded() async {
    if (!_isOnline) return;
    await _switchProfile(LocationProfile.waitingOnline);
  }

  /// The rider went "offline for new orders" while an order is still
  /// active. Going offline must NOT abandon the assigned delivery
  /// (blueprint §6): the backend stops sending new offers, but live
  /// tracking for the in-flight delivery continues — so the GPS stream
  /// keeps running on the matching active-delivery profile.
  ///
  /// [pickedUp]: whether the order has been picked up already (in
  /// transit to the customer) vs still heading to the store.
  Future<void> onWentOfflineDuringDelivery({required bool pickedUp}) async {
    // Tracking continues even though the rider is dispatch-offline.
    _isOnline = true;
    await _switchProfile(
      pickedUp
          ? LocationProfile.inTransitToCustomer
          : LocationProfile.acceptedToStore,
    );
  }

  /// Called from the map screen / home screen on mount to ensure the
  /// stream is running if the rider is already online (e.g. after a
  /// hot restart or app resume, or a fresh login on a device the
  /// backend already believes is online — same account, different
  /// phone). Set [hasActiveDelivery] when an accepted/picked-up order
  /// exists: going "offline for new orders" mid-delivery keeps
  /// tracking, so the stream must also restore for that case after a
  /// restart. Returns `true` once the GPS stream is confirmed running,
  /// `false` when it couldn't start (missing permission/service) so the
  /// caller can prompt the rider instead of silently leaving their live
  /// location stuck on whatever the last device reported.
  Future<bool> ensureRunningIfOnline({
    bool isOnline = false,
    bool hasActiveDelivery = false,
  }) async {
    if (!isOnline && !hasActiveDelivery) return false;
    _isOnline = true;
    if (isStreaming) return true;
    return _ensurePermissionAndStart(
      _currentProfile == LocationProfile.offline
          ? LocationProfile.waitingOnline
          : _currentProfile,
    );
  }

  Future<void> dispose() async {
    await _stop();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<bool> _ensurePermissionAndStart(LocationProfile profile) async {
    // Check / request permission first.
    final LocationPermissionResult result = await _permissionService
        .ensureWhileInUse();
    if (!result.canUseLocation) {
      // Permission denied or service off — can't stream.
      return false;
    }

    // Seed one immediate fix so the marker appears right away.
    final Position? seed = await _locationService.getCurrentPosition();
    if (seed != null) {
      _publish(seed);
    }

    await _startStream(profile);
    return true;
  }

  Future<void> _startStream(LocationProfile profile) async {
    await _subscription?.cancel();
    _subscription = null;
    _currentProfile = profile;

    if (profile == LocationProfile.offline) return;

    _subscription = _locationService
        .getPositionStream(profile)
        .listen(
          _publish,
          onError: (Object e) {
            // Non-fatal — keep the last known position.
            debugPrint('[LocationLifecycleManager] stream error: $e');
          },
        );
  }

  Future<void> _switchProfile(LocationProfile profile) async {
    if (_currentProfile == profile) return;
    await _startStream(profile);
  }

  Future<void> _stop() async {
    _currentProfile = LocationProfile.offline;
    await _subscription?.cancel();
    _subscription = null;
  }

  void _publish(Position p) {
    // Update the map marker notifier.
    _notifier.value = GeoPoint(p.latitude, p.longitude);

    // Upload to backend (throttled).
    final DateTime now = DateTime.now();
    final DateTime? last = _lastUploadAt;
    if (last != null && now.difference(last) < _minUploadInterval) return;
    _lastUploadAt = now;
    unawaited(_upload(p));
  }

  Future<void> _upload(Position p) async {
    // Socket primary transport.
    if (_socket.status == SocketStatus.connected) {
      _socket.emit('rider:location', <String, dynamic>{
        'latitude': p.latitude,
        'longitude': p.longitude,
      });
      return;
    }
    // REST fallback.
    try {
      await _deliveryApi.updateLocation(p.latitude, p.longitude);
    } catch (_) {
      // Best-effort — swallow upload errors.
    }
  }
}
