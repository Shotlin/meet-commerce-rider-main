import 'package:flutter/foundation.dart';

/// An immutable latitude/longitude value type that replaces
/// `google_maps_flutter.LatLng` across the application layer.
///
/// A plain geographic coordinate — rendering-agnostic since Big Phase 12
/// so future SDK swaps remain local to this file.
@immutable
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
