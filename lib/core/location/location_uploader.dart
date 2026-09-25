import 'package:geolocator/geolocator.dart';

import '../config/app_constants.dart';
import '../realtime/socket_client.dart';
import '../../features/delivery/data/delivery_api.dart';
import 'location_profile.dart';
import 'location_throttler.dart';

/// Orchestrates location upload decisions: throttling, socket-primary
/// transport, REST fallback, and periodic keepalive (R18).
///
/// Decision flow for each [onSample] call:
/// 1. Skip if the new position is a duplicate (moved < distanceFilter).
/// 2. Skip if the throttler budget is exhausted.
/// 3. Record the stamp via [SlidingWindowThrottler.accept].
/// 4. If socket is connected: emit `rider:location` via socket.
/// 5. If socket is disconnected, OR [_forceRestOnce] is set, OR a REST
///    keepalive is due, OR the last socket emit is older than
///    [AppConstants.locationSocketStaleThreshold]: call
///    [DeliveryApi.updateLocation].
/// 6. Update internal bookkeeping timestamps.
class LocationUploader {
  /// Creates a [LocationUploader].
  ///
  /// [throttler]   – sliding-window rate-budget enforcer.
  /// [socket]      – Socket.IO client for realtime transport.
  /// [deliveryApi] – REST fallback for location updates.
  LocationUploader({
    required SlidingWindowThrottler throttler,
    required SocketClient socket,
    required DeliveryApi deliveryApi,
  }) : _throttler = throttler,
       _socket = socket,
       _deliveryApi = deliveryApi;

  final SlidingWindowThrottler _throttler;
  final SocketClient _socket;
  final DeliveryApi _deliveryApi;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  Position? _lastEmitted;
  DateTime? _lastSocketAt;
  DateTime? _lastRestAt;

  /// When `true`, the next [onSample] call will force a REST upload in
  /// addition to (or instead of) the socket emit.
  bool _forceRestOnce = false;

  /// Minimum distance filter in metres used for duplicate detection.
  ///
  /// Updated by [switchProfile] to match the active profile's
  /// [ProfileConfig.distanceFilterMeters].
  int _distanceFilterMeters =
      LocationProfile.waitingOnline.config.distanceFilterMeters;

  /// Maximum interval between REST keepalive calls (60 seconds).
  static const Duration _restKeepaliveInterval = Duration(seconds: 60);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Processes a new GPS sample.
  ///
  /// [p]       – the new position.
  /// [now]     – the current wall-clock time (injected for testability).
  /// [orderId] – optional active order ID included in the socket payload.
  Future<void> onSample(Position p, DateTime now, {String? orderId}) async {
    // 1. Duplicate check.
    if (_isDuplicate(p)) return;

    // 2. Throttle check.
    if (!_throttler.canEmit(now)) return;

    // 3. Record the stamp.
    _throttler.accept(now);

    // 4. Determine whether to use REST.
    final bool socketConnected = isSocketConnected;
    final bool forceRest = _forceRestOnce;
    final bool keepaliveDue = _restKeepaliveDue(now);
    // A connected socket that has not carried a fix recently no longer
    // proves freshness to the backend, so the next sample is mirrored over
    // REST too (documented in AppConstants.locationSocketStaleThreshold).
    final bool socketStale = socketConnected && _socketIsStale(now);

    // 5a. Socket emit (when connected).
    if (socketConnected) {
      final Map<String, dynamic> payload = <String, dynamic>{
        'latitude': p.latitude,
        'longitude': p.longitude,
        if (orderId != null) 'orderId': orderId,
      };
      _socket.emit('rider:location', payload);
      _lastSocketAt = now;
    }

    // 5b. REST upload (when socket disconnected, forced, keepalive due, or
    //     the socket emit just shown above was itself overdue).
    if (!socketConnected || forceRest || keepaliveDue || socketStale) {
      try {
        await _deliveryApi.updateLocation(p.latitude, p.longitude);
        _lastRestAt = now;
      } catch (_) {
        // Swallow REST errors; the next sample will retry.
      }
    }

    // 6. Update bookkeeping.
    _lastEmitted = p;
    if (forceRest) {
      _forceRestOnce = false;
    }
  }

  /// Called when the app returns to the foreground.
  ///
  /// Forces the next [onSample] to send a REST update so the backend
  /// has a fresh position after the app was backgrounded (R18.3).
  void onAppResume() {
    _forceRestOnce = true;
  }

  /// Called when the rider transitions from offline to online.
  ///
  /// Forces the next [onSample] to send a REST update so the backend
  /// immediately knows the rider's position (R18.4).
  void onWentOnline() {
    _forceRestOnce = true;
  }

  /// Switches the active [LocationProfile], updating the throttler budget
  /// and the duplicate-detection distance filter.
  void switchProfile(LocationProfile profile) {
    _throttler.setBudget(profile.config.rateBudgetPerMinute);
    _distanceFilterMeters = profile.config.distanceFilterMeters;
  }

  /// Returns `true` when the underlying socket is connected.
  bool get isSocketConnected => _socket.status == SocketStatus.connected;

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` when [p] has not moved more than [_distanceFilterMeters]
  /// from the last emitted position.
  ///
  /// Always returns `false` when no position has been emitted yet.
  bool _isDuplicate(Position p) {
    final Position? last = _lastEmitted;
    if (last == null) return false;

    final double distanceMeters = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      p.latitude,
      p.longitude,
    );
    return distanceMeters < _distanceFilterMeters;
  }

  /// Returns `true` when a REST keepalive is due.
  ///
  /// A keepalive is due when no REST update has been sent within the last
  /// [_restKeepaliveInterval] (60 seconds).
  bool _restKeepaliveDue(DateTime now) {
    final DateTime? lastRest = _lastRestAt;
    if (lastRest == null) return false;
    return now.difference(lastRest) >= _restKeepaliveInterval;
  }

  /// Returns `true` when the last socket emit is older than
  /// [AppConstants.locationSocketStaleThreshold].
  ///
  /// This is the reconnect guard: while the socket is down (or quietly
  /// failing) `_lastSocketAt` stops advancing, so the first sample after the
  /// gap is mirrored over REST and the backend's authoritative store is not
  /// left holding a stale rider position.
  bool _socketIsStale(DateTime now) {
    final DateTime? lastSocket = _lastSocketAt;
    if (lastSocket == null) return true;
    return now.difference(lastSocket) >=
        AppConstants.locationSocketStaleThreshold;
  }
}
