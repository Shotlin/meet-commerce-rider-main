import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart' as fm;

import 'geo_point.dart';

/// An immutable axis-aligned geographic bounding box defined by a
/// [southwest] and [northeast] [GeoPoint] corner.
///
/// Validation rules (not enforced at construction time):
/// - `southwest.latitude  <= northeast.latitude`
/// - `southwest.longitude <= northeast.longitude`
///
/// Antimeridian wrapping is not supported — the rider app operates
/// within India, well clear of the antimeridian.
@immutable
class GeoBounds {
  const GeoBounds({required this.southwest, required this.northeast});

  final GeoPoint southwest;
  final GeoPoint northeast;

  /// Returns `true` when [p] lies inside or on the boundary of this box.
  bool contains(GeoPoint p) {
    return southwest.latitude <= p.latitude &&
        p.latitude <= northeast.latitude &&
        southwest.longitude <= p.longitude &&
        p.longitude <= northeast.longitude;
  }

  /// Convert to flutter_map's [fm.LatLngBounds] for `fitCamera` /
  /// `CameraFit.bounds`.
  fm.LatLngBounds toLatLngBounds() =>
      fm.LatLngBounds(southwest.toLatLng(), northeast.toLatLng());

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      other.southwest == southwest &&
      other.northeast == northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);

  @override
  String toString() => 'GeoBounds(sw: $southwest, ne: $northeast)';
}
