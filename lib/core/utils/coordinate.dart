import 'package:flutter/foundation.dart';

/// A geographic coordinate (latitude, longitude).
///
/// Construction validates that the coordinate falls within the WGS-84
/// range — latitude in `[-90, 90]`, longitude in `[-180, 180]` — and
/// throws [InvalidCoordinateException] otherwise. The same validation
/// is exposed via the static [Coordinate.validate] / [Coordinate.validateOrNull]
/// hooks so models that store nullable `double? lat, double? lng` can
/// share the invariant without holding a [Coordinate] instance.
///
/// This type lives in `core/utils` rather than the delivery feature
/// folder because coordinates are used by both the location subsystem
/// and the delivery models. Keeping the validation invariant in one
/// place is what lets every code path that produces a coordinate
/// guarantee the bounds (R28.3).
@immutable
class Coordinate {
  /// Constructs a coordinate, validating the supplied [lat] / [lng].
  ///
  /// Throws [InvalidCoordinateException.lat] or
  /// [InvalidCoordinateException.lng] when the corresponding dimension
  /// is out of range. The offending value is captured on the exception
  /// (and rendered in `toString()`) so callers and logs can report it.
  Coordinate(this.lat, this.lng) {
    Coordinate.validate(lat: lat, lng: lng);
  }

  /// Latitude in degrees, in `[-90, 90]`.
  final double lat;

  /// Longitude in degrees, in `[-180, 180]`.
  final double lng;

  /// Validates the supplied [lat] and [lng].
  ///
  /// Throws [InvalidCoordinateException] when either dimension is
  /// outside the valid range.
  static void validate({required double lat, required double lng}) {
    if (lat < -90 || lat > 90) {
      throw InvalidCoordinateException.lat(lat);
    }
    if (lng < -180 || lng > 180) {
      throw InvalidCoordinateException.lng(lng);
    }
  }

  /// Validates the supplied nullable [lat] and [lng].
  ///
  /// A null value is treated as "not provided" and skipped. Non-null
  /// values are validated using the same rules as [validate].
  ///
  /// Used by models that store coordinates as optional fields (e.g.
  /// [DeliveryAddress]) so the constructor and the JSON parser share
  /// the invariant.
  static void validateOrNull({double? lat, double? lng}) {
    if (lat != null && (lat < -90 || lat > 90)) {
      throw InvalidCoordinateException.lat(lat);
    }
    if (lng != null && (lng < -180 || lng > 180)) {
      throw InvalidCoordinateException.lng(lng);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Coordinate && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'Coordinate(lat=$lat, lng=$lng)';
}

/// Thrown when a latitude or longitude value falls outside the valid
/// geographic range (lat ∈ [-90, 90], lng ∈ [-180, 180]).
///
/// Constructed via [InvalidCoordinateException.lat] or
/// [InvalidCoordinateException.lng] so the offending dimension is
/// captured explicitly at the call site. The exception is `final`
/// (no further subclassing) and implements [Exception] so callers can
/// catch it generically or pattern-match specifically.
final class InvalidCoordinateException implements Exception {
  /// Constructs the exception for an out-of-range latitude.
  const InvalidCoordinateException.lat(double v) : field = 'lat', value = v;

  /// Constructs the exception for an out-of-range longitude.
  const InvalidCoordinateException.lng(double v) : field = 'lng', value = v;

  /// The dimension that failed validation: `'lat'` or `'lng'`.
  final String field;

  /// The out-of-range value that triggered the exception.
  final double value;

  @override
  String toString() =>
      'InvalidCoordinateException: $field=$value is out of valid range';
}
