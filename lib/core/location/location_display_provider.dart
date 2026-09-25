import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../maps/geo_point.dart';
import 'rider_location_provider.dart';

/// Holds the human-readable area name and raw coordinates for the
/// rider's current position.
@immutable
class LocationDisplay {
  const LocationDisplay({required this.position, this.areaName});

  final GeoPoint position;

  /// Reverse-geocoded area name from OSM Nominatim, e.g.
  /// "Bow Bazar, Kolkata, West Bengal".
  /// Null while the lookup is in progress or if it failed.
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
/// position via OSM Nominatim (free, no API key).
///
/// Debounces lookups to at most once every 30 seconds so we don't
/// hammer the public endpoint on every GPS tick.
///
/// INTERIM ONLY: reverse geocoding must move to Ola Maps (through the
/// backend's `/maps/ola/*` proxy) in Big Phase 12/13, which removes the last
/// runtime OpenStreetMap dependency from the app.
class LocationDisplayNotifier extends AsyncNotifier<LocationDisplay?> {
  static const Duration _debounce = Duration(seconds: 30);
  static const String _userAgent = 'meetcommerce-rider-app/0.1.0';

  DateTime? _lastLookupAt;
  http.Client? _client;

  @override
  Future<LocationDisplay?> build() async {
    _client = http.Client();
    ref.onDispose(() => _client?.close());

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
    try {
      final Uri url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json'
        '&lat=${pos.latitude}'
        '&lon=${pos.longitude}'
        '&zoom=14'
        '&addressdetails=1',
      );
      final http.Response resp = await (_client ?? http.Client())
          .get(url, headers: <String, String>{'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final dynamic json = jsonDecode(resp.body);
      if (json is! Map<String, dynamic>) return null;
      final Map<String, dynamic>? address =
          json['address'] as Map<String, dynamic>?;
      if (address == null) return null;

      // Build a short, readable area string.
      final String suburb =
          (address['suburb'] as String?) ??
          (address['neighbourhood'] as String?) ??
          (address['quarter'] as String?) ??
          '';
      final String city =
          (address['city'] as String?) ??
          (address['town'] as String?) ??
          (address['village'] as String?) ??
          '';
      final String state = (address['state'] as String?) ?? '';

      final List<String> parts = <String>[
        if (suburb.isNotEmpty) suburb,
        if (city.isNotEmpty) city,
        if (state.isNotEmpty) state,
      ];
      return parts.isEmpty
          ? (json['display_name'] as String?)
          : parts.join(', ');
    } catch (_) {
      return null;
    }
  }
}

/// Provider exposing the rider's current [LocationDisplay].
final AsyncNotifierProvider<LocationDisplayNotifier, LocationDisplay?>
locationDisplayProvider =
    AsyncNotifierProvider<LocationDisplayNotifier, LocationDisplay?>(
      LocationDisplayNotifier.new,
    );
