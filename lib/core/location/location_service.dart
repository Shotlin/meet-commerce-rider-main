import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_profile.dart';

/// Wraps [Geolocator] with profile-driven stream settings.
///
/// Each [LocationProfile] carries a [ProfileConfig] that specifies the
/// accuracy, distance filter, and rate budget. [LocationService] translates
/// those settings into the correct [LocationSettings] for Geolocator and
/// manages the lifecycle of the active stream subscription.
///
/// Responsibilities:
/// - Start / stop the Geolocator position stream based on the active profile.
/// - Provide a one-shot [getCurrentPosition] for initial fixes.
/// - Cancel the active subscription on [dispose].
class LocationService {
  StreamSubscription<Position>? _subscription;

  // ---------------------------------------------------------------------------
  // Streaming
  // ---------------------------------------------------------------------------

  /// Returns a continuous [Stream<Position>] configured for [profile].
  ///
  /// Cancels any previously active subscription before starting a new one.
  /// If [profile] is [LocationProfile.offline], an empty stream is returned
  /// and no Geolocator stream is started.
  ///
  /// The returned stream is a broadcast stream; multiple listeners are
  /// supported.
  Stream<Position> getPositionStream(LocationProfile profile) {
    // Cancel any existing subscription first.
    _subscription?.cancel();
    _subscription = null;

    if (profile == LocationProfile.offline) {
      return const Stream<Position>.empty();
    }

    final ProfileConfig cfg = profile.config;

    final LocationSettings settings = LocationSettings(
      accuracy: _mapAccuracy(cfg.accuracy),
      distanceFilter: cfg.distanceFilterMeters,
      timeLimit: null,
    );

    final StreamController<Position> controller =
        StreamController<Position>.broadcast();

    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // One-shot position
  // ---------------------------------------------------------------------------

  /// Returns the current device position, or `null` on timeout or error.
  ///
  /// Uses [LocationAccuracy.high] and a 10-second timeout. Returns `null`
  /// instead of throwing so callers can handle the absence gracefully.
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Cancels the active stream subscription, if any.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Maps the platform-free [LocationAccuracyTier] onto the geolocator
  /// package's [LocationAccuracy] enum.
  static LocationAccuracy _mapAccuracy(LocationAccuracyTier tier) {
    switch (tier) {
      case LocationAccuracyTier.off:
        return LocationAccuracy.lowest;
      case LocationAccuracyTier.medium:
        return LocationAccuracy.medium;
      case LocationAccuracyTier.high:
        return LocationAccuracy.high;
    }
  }
}
