import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'geo_point.dart';

/// Resolves a road-snapped polyline between two [GeoPoint]s.
///
/// Backed by the free public OSRM demo router (no API key, no
/// payment). The returned list contains the latitude / longitude
/// vertices of the route as it follows actual roads — the same
/// shape Google Maps would render as a blue navigation line.
///
/// Failures (timeout, non-2xx, parse error, no internet) collapse
/// silently to the straight-line fallback `[from, to]` so the map
/// always has *something* to draw.
class RouteService {
  RouteService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _defaultBaseUrl;

  static const String _defaultBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';

  final http.Client _client;
  final String _baseUrl;

  // Tiny LRU cache keyed by rounded endpoint coordinates so that
  // repeat lookups while the rider drifts < 100 m don't hammer the
  // public router.
  final Map<String, List<GeoPoint>> _cache = <String, List<GeoPoint>>{};
  static const int _maxCacheEntries = 16;

  /// Returns the road-following polyline from [from] → [to].
  /// Always returns at least 2 points; on any error the result is
  /// the straight-line `[from, to]`.
  Future<List<GeoPoint>> getRoute(GeoPoint from, GeoPoint to) async {
    final String key = _cacheKey(from, to);
    final List<GeoPoint>? cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // mark recent
      return cached;
    }

    try {
      final Uri url = Uri.parse(
        '$_baseUrl/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final http.Response resp = await _client
          .get(url)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return _fallback(from, to);
      }
      final dynamic decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return _fallback(from, to);
      if (decoded['code'] != 'Ok') return _fallback(from, to);
      final List<dynamic>? routes = decoded['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return _fallback(from, to);
      final Map<String, dynamic> first = routes.first as Map<String, dynamic>;
      final Map<String, dynamic>? geometry =
          first['geometry'] as Map<String, dynamic>?;
      if (geometry == null) return _fallback(from, to);
      final List<dynamic>? coords = geometry['coordinates'] as List<dynamic>?;
      if (coords == null || coords.length < 2) return _fallback(from, to);

      final List<GeoPoint> points = <GeoPoint>[];
      for (final dynamic raw in coords) {
        if (raw is List && raw.length >= 2) {
          final num lng = raw[0] as num;
          final num lat = raw[1] as num;
          points.add(GeoPoint(lat.toDouble(), lng.toDouble()));
        }
      }
      if (points.length < 2) return _fallback(from, to);

      _cache[key] = points;
      while (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      return points;
    } catch (_) {
      return _fallback(from, to);
    }
  }

  /// Round to ~110 m so micro-drift doesn't trigger fresh fetches.
  String _cacheKey(GeoPoint a, GeoPoint b) {
    String r(double v) => v.toStringAsFixed(3);
    return '${r(a.latitude)},${r(a.longitude)}->'
        '${r(b.latitude)},${r(b.longitude)}';
  }

  List<GeoPoint> _fallback(GeoPoint from, GeoPoint to) => <GeoPoint>[from, to];
}
