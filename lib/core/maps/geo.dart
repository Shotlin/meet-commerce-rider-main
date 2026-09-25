import 'dart:math' as math;

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

  static double _toRad(double degrees) => degrees * math.pi / 180.0;
}
