import '../config/app_constants.dart';

/// Rider location profile.
///
/// Each profile drives three things:
/// - GPS accuracy and distance filter passed to Geolocator
///   ([LocationProfileConfig.distanceFilterMeters], [LocationAccuracyTier])
/// - Sliding-window upload budget passed to [SlidingWindowThrottler]
///   ([LocationProfileConfig.rateBudgetPerMinute])
/// - Min-interval hint used by the uploader for batching
///   ([LocationProfileConfig.minInterval])
///
/// The four states map directly to the spec (R17.1-R17.3):
///
/// | profile               | accuracy | distance | budget/min |
/// |-----------------------|----------|----------|------------|
/// | offline               | (off)    | (off)    | 0          |
/// | waitingOnline         | medium   | 75 m     | 2          |
/// | acceptedToStore       | high     | 30 m     | 6          |
/// | inTransitToCustomer   | high     | 20 m     | 12         |
///
/// Kept platform-free (no Geolocator import) so unit tests don't need
/// the platform plugin. Task 8.1 maps [LocationAccuracyTier] onto the
/// concrete `LocationAccuracy` from `geolocator`.
enum LocationProfile {
  /// Rider is offline. No stream, no uploads.
  offline,

  /// Rider is online without an Active_Delivery.
  waitingOnline,

  /// Rider has accepted an offer; navigating to the store.
  acceptedToStore,

  /// Rider has picked up the order; navigating to the customer.
  inTransitToCustomer,
}

/// Coarse accuracy tier used by [LocationProfileConfig]. Mapped to
/// `LocationAccuracy` from the geolocator package by Task 8.1.
enum LocationAccuracyTier {
  /// Streaming is disabled (used by [LocationProfile.offline]).
  off,

  /// Equivalent to `LocationAccuracy.medium`.
  medium,

  /// Equivalent to `LocationAccuracy.high`.
  high,
}

/// Convenience getter so call sites can write `LocationProfile.waitingOnline.config`
/// instead of `LocationProfileConfig.forProfile(LocationProfile.waitingOnline)`.
extension LocationProfileConfigX on LocationProfile {
  /// Canonical [LocationProfileConfig] for this profile.
  LocationProfileConfig get config => LocationProfileConfig.forProfile(this);
}

/// Backwards-compat alias for [LocationProfileConfig].
typedef ProfileConfig = LocationProfileConfig;

/// Per-profile configuration values.
class LocationProfileConfig {
  /// Constructs an explicit config. Most callers go through
  /// [LocationProfileConfig.forProfile].
  const LocationProfileConfig({
    required this.accuracy,
    required this.distanceFilterMeters,
    required this.rateBudgetPerMinute,
    required this.minInterval,
  });

  /// Resolves the canonical config for [profile].
  factory LocationProfileConfig.forProfile(LocationProfile profile) {
    switch (profile) {
      case LocationProfile.offline:
        return const LocationProfileConfig(
          accuracy: LocationAccuracyTier.off,
          distanceFilterMeters: 0,
          rateBudgetPerMinute: 0,
          minInterval: Duration.zero,
        );
      case LocationProfile.waitingOnline:
        return const LocationProfileConfig(
          accuracy: LocationAccuracyTier.medium,
          distanceFilterMeters:
              AppConstants.locationDistanceFilterWaitingMeters,
          rateBudgetPerMinute: AppConstants.locationBudgetWaitingPerMinute,
          minInterval: Duration(seconds: 30),
        );
      case LocationProfile.acceptedToStore:
        return const LocationProfileConfig(
          accuracy: LocationAccuracyTier.high,
          distanceFilterMeters:
              AppConstants.locationDistanceFilterAcceptedMeters,
          rateBudgetPerMinute: AppConstants.locationBudgetAcceptedPerMinute,
          minInterval: Duration(seconds: 10),
        );
      case LocationProfile.inTransitToCustomer:
        return const LocationProfileConfig(
          accuracy: LocationAccuracyTier.high,
          distanceFilterMeters:
              AppConstants.locationDistanceFilterInTransitMeters,
          rateBudgetPerMinute: AppConstants.locationBudgetInTransitPerMinute,
          minInterval: Duration(seconds: 5),
        );
    }
  }

  /// GPS accuracy tier.
  final LocationAccuracyTier accuracy;

  /// Distance filter in metres for the underlying location stream.
  final int distanceFilterMeters;

  /// Maximum number of uploads permitted in a 60-second sliding window.
  final int rateBudgetPerMinute;

  /// Suggested minimum interval between consecutive uploads.
  final Duration minInterval;
}
