import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as ll;

/// An immutable latitude/longitude value type that replaces
/// `google_maps_flutter.LatLng` across the application layer.
///
/// Bridges to/from [ll.LatLng] at the `flutter_map` boundary only,
/// so future SDK swaps remain local to this file.
@immutable
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Convert to [ll.LatLng] for `flutter_map` consumption.
  ll.LatLng toLatLng() => ll.LatLng(latitude, longitude);

  /// Construct from a [ll.LatLng] value.
  factory GeoPoint.fromLatLng(ll.LatLng p) => GeoPoint(p.latitude, p.longitude);

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
