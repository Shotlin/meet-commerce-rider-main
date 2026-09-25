import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../maps/geo_point.dart';
import '../maps/rider_maps_service.dart';
import 'rider_location_provider.dart';

/// Holds the human-readable area name and raw coordinates for the
/// rider's current position.
@immutable
class LocationDisplay {
  const LocationDisplay({required this.position, this.areaName});

  final GeoPoint position;

  /// Reverse-geocoded area name from Ola Maps via the backend proxy,
  /// e.g. "Salt Lake, Kolkata". Null while the lookup is in progress
  /// or if it failed (callers show coordinates instead).
  final String? areaName;

  @override
  bool operator ==(Object other) =>
      other is LocationDisplay &&
      other.position == position &&
      other.areaName == areaName;

  @override
  int get hashCode => Object.hash(position, areaName);
}

/// Watches [riderLocationNotifierProvider] and reverse-geocodes the
/// position through the backend's Ola Maps proxy (`/maps/ola/
/// reverse-geocode`) — the API key stays server-side and the last
/// runtime OpenStreetMap dependency is gone (Big Phase 12).
///
/// Debounces lookups to at most once every 30 seconds so a moving
/// rider doesn't spam the proxied, quota-limited API on every GPS tick.
class LocationDisplayNotifier extends AsyncNotifier<LocationDisplay?> {
  static const Duration _debounce = Duration(seconds: 30);

  DateTime? _lastLookupAt;

  @override
  Future<LocationDisplay?> build() async {
    // Watch the rider location notifier.
    final ValueNotifier<GeoPoint?> notifier = ref.watch(
      riderLocationNotifierProvider,
    );

    // Listen for changes.
    notifier.addListener(_onPositionChanged);
    ref.onDispose(() => notifier.removeListener(_onPositionChanged));

    // Seed with current value.
    final GeoPoint? current = notifier.value;
    if (current != null) {
      return _buildDisplay(current);
    }
    return null;
  }

  void _onPositionChanged() {
    final GeoPoint? pos = ref.read(riderLocationNotifierProvider).value;
    if (pos == null) return;
    // Debounce: skip if we geocoded this position recently.
    final DateTime now = DateTime.now();
    final DateTime? last = _lastLookupAt;
    if (last != null && now.difference(last) < _debounce) {
      // Still update the position even if we skip the geocode.
      final LocationDisplay? prev = state.value;
      state = AsyncData<LocationDisplay?>(
        LocationDisplay(position: pos, areaName: prev?.areaName),
      );
      return;
    }
    // Trigger a fresh geocode.
    state = const AsyncLoading<LocationDisplay?>();
    unawaited(_geocode(pos));
  }

  Future<LocationDisplay?> _buildDisplay(GeoPoint pos) async {
    final String? name = await _reverseGeocode(pos);
    _lastLookupAt = DateTime.now();
    return LocationDisplay(position: pos, areaName: name);
  }

  Future<void> _geocode(GeoPoint pos) async {
    final String? name = await _reverseGeocode(pos);
    _lastLookupAt = DateTime.now();
    state = AsyncData<LocationDisplay?>(
      LocationDisplay(position: pos, areaName: name),
    );
  }

  Future<String?> _reverseGeocode(GeoPoint pos) async {
    return ref.read(riderMapsServiceProvider).getAreaLabel(pos);
  }
}

/// Provider exposing the rider's current [LocationDisplay].
final AsyncNotifierProvider<LocationDisplayNotifier, LocationDisplay?>
locationDisplayProvider =
    AsyncNotifierProvider<LocationDisplayNotifier, LocationDisplay?>(
      LocationDisplayNotifier.new,
    );
