import 'dart:math' as math;

import 'geo_bounds.dart';
import 'geo_point.dart';

/// Pure, side-effect-free geographic utility functions.
///
/// No `dart:io` or `dart:ui` dependency — safe to use in pure Dart unit tests.
abstract final class Geo {
  /// Earth's mean radius in metres (as specified in the design doc).
  static const double _earthRadiusM = 6371000.0;

  /// Great-circle distance in metres between [a] and [b] using the
  /// Haversine formula with R = 6 371 000 m.
  ///
  /// Properties guaranteed:
  /// - `distanceMeters(a, b) >= 0`
  /// - `distanceMeters(a, b) == distanceMeters(b, a)` (within IEEE-754 rounding)
  /// - `distanceMeters(a, a) == 0.0`
  /// - `distanceMeters(a, b) <= π * 6_371_000` (half the Earth's circumference)
  static double distanceMeters(GeoPoint a, GeoPoint b) {
    final phi1 = _toRad(a.latitude);
    final phi2 = _toRad(b.latitude);
    final dPhi = _toRad(b.latitude - a.latitude);
    final dLambda = _toRad(b.longitude - a.longitude);

    final h =
        math.pow(math.sin(dPhi / 2), 2) +
        math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);

    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));

    return _earthRadiusM * c;
  }

  /// Smallest axis-aligned bounding box containing both [a] and [b].
  ///
  /// - Both null → returns `null`.
  /// - Exactly one non-null → delegates to [inflatePoint] for a non-degenerate box.
  /// - Both non-null → returns the min/max bounds containing both points.
  static GeoBounds? boundsOf(GeoPoint? a, GeoPoint? b) {
    if (a == null && b == null) return null;
    if (a != null && b == null) return inflatePoint(a);
    if (a == null && b != null) return inflatePoint(b);

    // Both non-null.
    final minLat = math.min(a!.latitude, b!.latitude);
    final maxLat = math.max(a.latitude, b.latitude);
    final minLng = math.min(a.longitude, b.longitude);
    final maxLng = math.max(a.longitude, b.longitude);

    return GeoBounds(
      southwest: GeoPoint(minLat, minLng),
      northeast: GeoPoint(maxLat, maxLng),
    );
  }

  /// Inflate a single point [p] by [epsilonDeg] degrees in each cardinal
  /// direction, producing a non-degenerate [GeoBounds].
  ///
  /// The resulting bounds satisfies:
  /// - `northeast.latitude  > southwest.latitude`
  /// - `northeast.longitude > southwest.longitude`
  /// - `bounds.contains(p) == true`
  static GeoBounds inflatePoint(GeoPoint p, {double epsilonDeg = 0.005}) {
    return GeoBounds(
      southwest: GeoPoint(p.latitude - epsilonDeg, p.longitude - epsilonDeg),
      northeast: GeoPoint(p.latitude + epsilonDeg, p.longitude + epsilonDeg),
    );
  }

  /// Geodetic midpoint between [a] and [b].
  ///
  /// Uses the spherical midpoint formula for accuracy over long distances.
  static GeoPoint midpoint(GeoPoint a, GeoPoint b) {
    final phi1 = _toRad(a.latitude);
    final lambda1 = _toRad(a.longitude);
    final phi2 = _toRad(b.latitude);
    final dLambda = _toRad(b.longitude - a.longitude);

    final bx = math.cos(phi2) * math.cos(dLambda);
    final by = math.cos(phi2) * math.sin(dLambda);

    final phiMid = math.atan2(
      math.sin(phi1) + math.sin(phi2),
      math.sqrt(math.pow(math.cos(phi1) + bx, 2) + math.pow(by, 2)),
    );
    final lambdaMid = lambda1 + math.atan2(by, math.cos(phi1) + bx);

    return GeoPoint(_toDeg(phiMid), _toDeg(lambdaMid));
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static double _toRad(double deg) => deg * math.pi / 180.0;
  static double _toDeg(double rad) => rad * 180.0 / math.pi;
}
