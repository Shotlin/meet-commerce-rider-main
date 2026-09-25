import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../maps/geo_point.dart';

/// Singleton [ValueNotifier] holding the rider's most recent
/// [GeoPoint], or `null` while the GPS fix is unknown.
///
/// Smoothness invariant (R25.1): the active delivery map screen
/// drives marker / polyline updates from this notifier through a
/// [ValueListenableBuilder]. That keeps GPS pings out of the Riverpod
/// rebuild graph so the surrounding [Scaffold] (status pill, sheet,
/// recenter button) never rebuilds when only the rider's position
/// changes.
///
/// The notifier is the **transport** for map state. The
/// `LocationUploader` / `LocationController` is responsible for
/// *publishing* into this notifier when a new GPS sample arrives;
/// nothing here imports `geolocator` so the provider stays pure for
/// unit tests and lets the screen widget tests inject a synthetic
/// [GeoPoint] directly.
final Provider<ValueNotifier<GeoPoint?>> riderLocationNotifierProvider =
    Provider<ValueNotifier<GeoPoint?>>((Ref ref) {
      final ValueNotifier<GeoPoint?> notifier = ValueNotifier<GeoPoint?>(null);
      ref.onDispose(notifier.dispose);
      return notifier;
    });
