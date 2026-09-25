import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../maps/geo_point.dart';
import 'location_profile.dart';
import 'location_service.dart';

/// Publishes the rider's GPS samples into the
/// [riderLocationNotifierProvider]'s notifier.
///
/// Runs as a long-lived singleton owned by Riverpod. On [start] it
/// acquires one fix via [LocationService.getCurrentPosition] and
/// then subscribes to the position stream for the supplied
/// [LocationProfile]. Cancelled by [stop] / dispose.
class RiderLocationPublisher {
  RiderLocationPublisher({
    required ValueNotifier<GeoPoint?> notifier,
    required LocationService locationService,
  }) : _notifier = notifier,
       _locationService = locationService;

  final ValueNotifier<GeoPoint?> _notifier;
  final LocationService _locationService;

  StreamSubscription<Position>? _subscription;
  bool _started = false;

  /// Whether the publisher is actively producing samples.
  bool get isRunning => _started;

  /// Start producing samples for [profile]. Idempotent — calling
  /// `start` again with a new profile re-binds the underlying
  /// stream without losing the most recent value.
  Future<void> start({
    LocationProfile profile = LocationProfile.waitingOnline,
  }) async {
    _started = true;

    // Seed one fix synchronously so the map can render the rider
    // marker before the first stream tick lands.
    if (_notifier.value == null) {
      final Position? seed = await _locationService.getCurrentPosition();
      if (seed != null) {
        _notifier.value = GeoPoint(seed.latitude, seed.longitude);
      }
    }

    await _subscription?.cancel();
    _subscription = _locationService
        .getPositionStream(profile)
        .listen(
          (Position p) {
            _notifier.value = GeoPoint(p.latitude, p.longitude);
          },
          onError: (Object _) {
            // Geolocator surfacing an error mid-stream is non-fatal;
            // the notifier keeps its last good value.
          },
        );
  }

  /// Stop the active stream subscription. Idempotent.
  Future<void> stop() async {
    _started = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
  }
}
