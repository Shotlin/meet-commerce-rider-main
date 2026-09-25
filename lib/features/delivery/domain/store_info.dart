import 'package:flutter/foundation.dart';

import '../../../core/utils/coordinate.dart';
import '../data/order_parser.dart';

/// Store information returned by `GET /delivery/store-info`.
///
/// The live backend returns `lat`/`lng` as numbers (not strings) for
/// this route. The parser accepts both numeric and string forms for
/// robustness.
///
/// Coordinate validation is applied in the constructor via
/// [Coordinate.validate], throwing [InvalidCoordinateException] for
/// out-of-range values (R28.3). The default `(0, 0)` returned by the
/// live backend when the store has not been configured passes
/// validation; callers detect the unconfigured case via
/// [isConfigured].
@immutable
class StoreInfo {
  /// Constructs a store info record.
  ///
  /// Throws [InvalidCoordinateException] when [lat] or [lng] is outside
  /// the valid geographic range.
  StoreInfo({
    required this.name,
    required this.address,
    this.phone,
    required this.lat,
    required this.lng,
  }) {
    Coordinate.validate(lat: lat, lng: lng);
  }

  /// Lenient parser. Accepts `storeName`/`name`, `storeAddress`/`address`,
  /// `storePhone`/`phone`, `storeLat`/`lat`, `storeLng`/`lng`.
  factory StoreInfo.fromJson(Map<String, dynamic> j) {
    return StoreInfo(
      name: OrderParser.readString(j, 'name', 'storeName'),
      address: OrderParser.readString(j, 'address', 'storeAddress'),
      phone: OrderParser.readStringOpt(j, 'phone', 'storePhone'),
      lat: OrderParser.readDouble(j, 'lat', 'storeLat'),
      lng: OrderParser.readDouble(j, 'lng', 'storeLng'),
    );
  }

  /// Serialises to camelCase JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'address': address,
    if (phone != null) 'phone': phone,
    'lat': lat,
    'lng': lng,
  };

  /// Returns a copy with the supplied fields replaced.
  StoreInfo copyWith({
    String? name,
    String? address,
    String? phone,
    double? lat,
    double? lng,
  }) {
    return StoreInfo(
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  /// Store display name.
  final String name;

  /// Store street address.
  final String address;

  /// Store contact phone. May be empty string (live backend returns `""`).
  final String? phone;

  /// Store latitude.
  final double lat;

  /// Store longitude.
  final double lng;

  /// True when the store coordinates have been configured by the
  /// platform (i.e. they are not the default `(0, 0)` sentinel).
  ///
  /// The live backend returns `lat: 0, lng: 0` for stores that have
  /// not had a real location assigned yet. UI / map code should use
  /// [isConfigured] to decide whether to fit the camera to the store
  /// position or fall back to the order payload coordinates.
  bool get isConfigured => !(lat == 0.0 && lng == 0.0);

  /// Backwards-compatible alias for the inverse of [isConfigured].
  ///
  /// Kept for callers that read the previous "unset" signal.
  bool get isLocationUnset => !isConfigured;

  @override
  bool operator ==(Object other) {
    return other is StoreInfo &&
        other.name == name &&
        other.address == address &&
        other.phone == phone &&
        other.lat == lat &&
        other.lng == lng;
  }

  @override
  int get hashCode => Object.hash(name, address, phone, lat, lng);

  @override
  String toString() => 'StoreInfo(name=$name, lat=$lat, lng=$lng)';
}
