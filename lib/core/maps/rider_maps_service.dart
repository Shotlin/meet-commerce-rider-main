import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../providers.dart' show apiClientProvider;
import '../network/api_envelope.dart';
import 'geo_point.dart';

/// Whether Ola Maps is usable, plus the style URL to render it with.
@immutable
class OlaMapsAvailability {
  /// Constructs the availability snapshot explicitly.
  const OlaMapsAvailability({required this.configured, this.styleUrl});

  /// No working key is configured dashboard-side — callers must show
  /// their graceful fallback instead of a map.
  static const OlaMapsAvailability unconfigured = OlaMapsAvailability(
    configured: false,
  );

  final bool configured;

  /// A self-contained MapLibre style document URL served by the
  /// backend's key-stitching proxy (glyphs, sprite and every nested
  /// TileJSON carry the key server-side). Null when unconfigured.
  final String? styleUrl;
}

/// A driving route between two points.
@immutable
class RiderRoute {
  /// Constructs a route explicitly.
  const RiderRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  /// Road-following polyline vertices (origin first, destination last).
  final List<GeoPoint> points;

  final int distanceMeters;

  final int durationSeconds;
}

/// Ola Maps access for the rider app, entirely proxied through the Meet
/// Commerce backend (`/maps/ola/*`) so the provider's API key never
/// ships inside the app build — rotating it is a dashboard-only change
/// (Big Phase 12 architecture decision; mirrors the customer app's
/// production-proven integration).
///
/// Rendering happens in `RiderMap` (MapLibre native on both platforms)
/// pointed at [getStyle]'s style URL; routes come from the backend's
/// Ola Directions proxy with the same straight-line fallback contract
/// the interim OSRM service had, so the map always has something to
/// draw and callers never special-case "no route".
class RiderMapsService {
  /// Wraps the supplied [client].
  RiderMapsService(this._client);

  static const double _fallbackMetersPerSecond = 6.5;

  final ApiClient _client;

  /// The MapLibre style URL for the rider map. Never throws — a
  /// backend/config failure reads as `configured: false` so the map
  /// surfaces its fallback instead of an error screen.
  Future<OlaMapsAvailability> getStyle() async {
    try {
      final ApiEnvelope<Map<String, dynamic>> envelope = await _client
          .get<Map<String, dynamic>>(
            '/maps/ola/style-url',
            parseData: _requireMap,
          );
      final Map<String, dynamic>? data = envelope.data;
      if (data == null || data['configured'] != true) {
        return OlaMapsAvailability.unconfigured;
      }
      final String? styleUrl = (data['styleUrl'] as String?)?.trim();
      if (styleUrl == null || styleUrl.isEmpty) {
        return OlaMapsAvailability.unconfigured;
      }
      return OlaMapsAvailability(
        configured: true,
        // MapLibre fetches the style itself, outside Dio and its base
        // URL. A reverse proxy can report `http` upstream even though
        // the public API is HTTPS, which Android rightly blocks as
        // clear-text traffic and leaves a black canvas — the customer
        // app hit exactly this. The API origin is authoritative, so
        // preserve its HTTPS scheme for a style URL on the same host.
        styleUrl: _securePublicStyleUrl(styleUrl),
      );
    } catch (_) {
      return OlaMapsAvailability.unconfigured;
    }
  }

  /// Driving route between two points via the backend's Ola Directions
  /// proxy. Falls back to a straight line on any failure so the map
  /// always has something to draw.
  Future<RiderRoute> getRoute(GeoPoint origin, GeoPoint destination) async {
    if (!_isValid(origin) || !_isValid(destination)) {
      return _straightLine(origin, destination);
    }
    try {
      final ApiEnvelope<Map<String, dynamic>> envelope = await _client
          .get<Map<String, dynamic>>(
            '/maps/ola/directions',
            queryParameters: <String, dynamic>{
              'originLat': origin.latitude,
              'originLng': origin.longitude,
              'destLat': destination.latitude,
              'destLng': destination.longitude,
            },
            parseData: _requireMap,
          );
      final Map<String, dynamic>? data = envelope.data;
      if (data == null) return _straightLine(origin, destination);
      final Map<String, dynamic> result = _asMap(data['result']);
      final List<GeoPoint> points = _asList(
        result['points'],
      ).map(_pointFrom).whereType<GeoPoint>().toList(growable: false);
      final int? distanceMeters = _asInt(result['distanceMeters']);
      final int? durationSeconds = _asInt(result['durationSeconds']);
      if (points.isEmpty || distanceMeters == null || durationSeconds == null) {
        return _straightLine(origin, destination);
      }
      return RiderRoute(
        points: points,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
      );
    } catch (_) {
      return _straightLine(origin, destination);
    }
  }

  /// A short human-readable area label for a coordinate ("Salt Lake,
  /// Kolkata") via the backend's Ola reverse-geocode proxy — the
  /// location freshness line's source. Null when nothing useful comes
  /// back (callers show coordinates instead).
  Future<String?> getAreaLabel(GeoPoint point) async {
    if (!_isValid(point)) return null;
    try {
      final ApiEnvelope<Map<String, dynamic>> envelope = await _client
          .get<Map<String, dynamic>>(
            '/maps/ola/reverse-geocode',
            queryParameters: <String, dynamic>{
              'lat': point.latitude,
              'lng': point.longitude,
            },
            parseData: _requireMap,
          );
      final Map<String, dynamic>? data = envelope.data;
      if (data == null) return null;
      final Map<String, dynamic> result = _asMap(data['result']);
      final List<dynamic> results = _asList(result['results']);
      if (results.isEmpty) return null;
      final Map<String, dynamic> first = _asMap(results.first);
      final List<Map<String, dynamic>> components = _asList(
        first['address_components'],
      ).map(_asMap).toList(growable: false);

      String component(String type) => _componentByType(components, type);
      String subLocality = component('sublocality');
      if (subLocality.isEmpty) {
        subLocality = component('sublocality_level_1');
      }
      final String city = component('locality').isEmpty
          ? component('administrative_area_level_2')
          : component('locality');

      final String? area = _firstNonEmpty(<String>[subLocality, city]);
      if (area != null) return area;

      final String formatted = (first['formatted_address'] as String?) ?? '';
      if (formatted.contains(',')) {
        return formatted.split(',').skip(1).join(',').trim();
      }
      return formatted.isEmpty ? null : formatted;
    } catch (_) {
      return null;
    }
  }

  // ─── helpers ───────────────────────────────────────────────────────

  String? _securePublicStyleUrl(String rawUrl) {
    final Uri? styleUri = Uri.tryParse(rawUrl);
    final Uri? apiUri = Uri.tryParse(_client.baseUrl);
    if (styleUri == null || apiUri == null) return rawUrl;
    if (styleUri.scheme == 'http' &&
        apiUri.scheme == 'https' &&
        styleUri.host == apiUri.host) {
      // No explicit port: a Uri without one inherits the scheme default,
      // while `port: 0` serializes literally and is rejected by
      // MapLibre's native URL parser (customer-app lesson).
      return styleUri.replace(scheme: 'https').toString();
    }
    return rawUrl;
  }

  RiderRoute _straightLine(GeoPoint origin, GeoPoint destination) {
    final double meters = _haversineMeters(origin, destination);
    final int safeDistance = meters.round() <= 0 ? 1 : meters.round();
    return RiderRoute(
      points: <GeoPoint>[origin, destination],
      distanceMeters: safeDistance,
      durationSeconds: (meters / _fallbackMetersPerSecond).ceil(),
    );
  }

  static bool _isValid(GeoPoint p) =>
      p.latitude != 0 ||
      p.longitude != 0; // 0,0 is never a valid operational point

  static double _haversineMeters(GeoPoint a, GeoPoint b) {
    const double earthRadius = 6371000;
    final double dLat = _degreesToRadians(b.latitude - a.latitude);
    final double dLng = _degreesToRadians(b.longitude - a.longitude);
    final double lat1 = _degreesToRadians(a.latitude);
    final double lat2 = _degreesToRadians(b.latitude);
    final double h =
        math.pow(math.sin(dLat / 2), 2).toDouble() +
        math.cos(lat1) *
            math.cos(lat2) *
            math.pow(math.sin(dLng / 2), 2).toDouble();
    return 2 * earthRadius * math.asin(math.sqrt(h));
  }

  static double _degreesToRadians(double degrees) =>
      degrees * 3.141592653589793 / 180.0;

  static Map<String, dynamic> _requireMap(Object? raw) {
    if (raw is Map) {
      return raw.map((Object? k, Object? v) => MapEntry('$k', v));
    }
    return const <String, dynamic>{};
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) {
      return value.map((Object? k, Object? v) => MapEntry('$k', v));
    }
    return const <String, dynamic>{};
  }

  static List<dynamic> _asList(Object? value) =>
      value is List ? value : const <dynamic>[];

  static GeoPoint? _pointFrom(Object? value) {
    final Map<String, dynamic> point = _asMap(value);
    final double? lat = _asDouble(point['lat']);
    final double? lng = _asDouble(point['lng']);
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _firstNonEmpty(List<String> values) {
    for (final String value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static String _componentByType(
    List<Map<String, dynamic>> components,
    String type,
  ) {
    for (final Map<String, dynamic> component in components) {
      final List<dynamic> types = component['types'] is List
          ? component['types'] as List<dynamic>
          : const <dynamic>[];
      if (types.contains(type)) {
        return ((component['long_name'] as String?) ?? '').trim();
      }
    }
    return '';
  }
}

/// Ola Maps access via the backend's key-stitching proxy — the API key
/// never ships in the app (Big Phase 12 architecture decision).
final Provider<RiderMapsService> riderMapsServiceProvider =
    Provider<RiderMapsService>((Ref ref) {
      return RiderMapsService(ref.watch(apiClientProvider));
    });
