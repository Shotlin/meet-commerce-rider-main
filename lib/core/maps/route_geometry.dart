import 'dart:math' as math;

import 'geo_point.dart';

/// Where a rider sits relative to a road-following route polyline.
class RouteProjection {
  const RouteProjection({
    required this.snapped,
    required this.segmentIndex,
    required this.offRouteMeters,
    required this.remainingMeters,
  });

  /// Closest point on the route to the rider.
  final GeoPoint snapped;

  /// Index `i` of the segment `points[i] → points[i + 1]` holding [snapped].
  final int segmentIndex;

  /// Straight-line distance from the rider to [snapped]. Large = off route.
  final double offRouteMeters;

  /// Distance along the route from [snapped] to its end.
  final double remainingMeters;
}

/// Pure polyline maths for the navigation screen. Segments are projected on
/// a local equirectangular plane around the rider, which is accurate to well
/// under a metre at city scale — far below GPS noise.
abstract final class RouteGeometry {
  static const double _earthRadiusM = 6371000.0;

  /// Total length of [points] in metres.
  static double lengthMeters(List<GeoPoint> points) {
    double total = 0;
    for (int i = 0; i < points.length - 1; i++) {
      total += _haversine(points[i], points[i + 1]);
    }
    return total;
  }

  /// Snaps [rider] to the nearest point on [points] (needs ≥ 2 points).
  static RouteProjection? project(List<GeoPoint> points, GeoPoint rider) {
    if (points.length < 2) return null;
    final double cosLat = math.cos(rider.latitude * math.pi / 180.0);

    double bestDistance = double.infinity;
    int bestSegment = 0;
    double bestT = 0;

    // Rider at the origin; everything in metres east/north of it.
    (double, double) toXY(GeoPoint p) => (
      (p.longitude - rider.longitude) * math.pi / 180.0 * _earthRadiusM * cosLat,
      (p.latitude - rider.latitude) * math.pi / 180.0 * _earthRadiusM,
    );

    for (int i = 0; i < points.length - 1; i++) {
      final (double ax, double ay) = toXY(points[i]);
      final (double bx, double by) = toXY(points[i + 1]);
      final double dx = bx - ax;
      final double dy = by - ay;
      final double lenSq = dx * dx + dy * dy;
      // Closest point on a→b to the origin.
      final double t = lenSq == 0
          ? 0
          : (-(ax * dx + ay * dy) / lenSq).clamp(0.0, 1.0);
      final double px = ax + t * dx;
      final double py = ay + t * dy;
      final double d = math.sqrt(px * px + py * py);
      if (d < bestDistance) {
        bestDistance = d;
        bestSegment = i;
        bestT = t;
      }
    }

    final GeoPoint a = points[bestSegment];
    final GeoPoint b = points[bestSegment + 1];
    final GeoPoint snapped = GeoPoint(
      a.latitude + (b.latitude - a.latitude) * bestT,
      a.longitude + (b.longitude - a.longitude) * bestT,
    );

    double remaining = _haversine(snapped, b);
    for (int i = bestSegment + 1; i < points.length - 1; i++) {
      remaining += _haversine(points[i], points[i + 1]);
    }

    return RouteProjection(
      snapped: snapped,
      segmentIndex: bestSegment,
      offRouteMeters: bestDistance,
      remainingMeters: remaining,
    );
  }

  /// The not-yet-travelled part of the route: [projection]'s snapped point
  /// followed by every vertex after it.
  static List<GeoPoint> remainingPoints(
    List<GeoPoint> points,
    RouteProjection projection,
  ) {
    return <GeoPoint>[
      projection.snapped,
      ...points.sublist(projection.segmentIndex + 1),
    ];
  }

  static double _haversine(GeoPoint a, GeoPoint b) {
    final double dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final double dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final double lat1 = a.latitude * math.pi / 180.0;
    final double lat2 = b.latitude * math.pi / 180.0;
    final double h =
        math.pow(math.sin(dLat / 2), 2).toDouble() +
        math.cos(lat1) *
            math.cos(lat2) *
            math.pow(math.sin(dLng / 2), 2).toDouble();
    return 2 * _earthRadiusM * math.asin(math.sqrt(h));
  }
}
