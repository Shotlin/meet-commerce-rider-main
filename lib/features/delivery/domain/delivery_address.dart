import 'package:flutter/foundation.dart';

import '../../../core/utils/coordinate.dart';
import '../data/order_parser.dart';

/// A physical address used in delivery orders.
///
/// Accepts both `lat`/`lng` and `latitude`/`longitude` field names from
/// JSON (the live backend uses both shapes across different routes).
/// Coordinate values may be strings or numbers — the parser handles
/// both because the profile endpoint returns coordinates as strings
/// while store-info returns them as numbers.
///
/// The constructor enforces the same coordinate-range invariant as the
/// parser via [Coordinate.validateOrNull], throwing
/// [InvalidCoordinateException] on out-of-range values (R28.3).
@immutable
class DeliveryAddress {
  /// Constructs a delivery address.
  ///
  /// Throws [InvalidCoordinateException] when [lat] or [lng] is
  /// provided but outside the valid geographic range.
  DeliveryAddress({
    required this.name,
    required this.address,
    this.landmark,
    this.phone,
    this.lat,
    this.lng,
  }) {
    Coordinate.validateOrNull(lat: lat, lng: lng);
  }

  /// Display name (store name or customer name).
  final String name;

  /// Street address.
  final String address;

  /// Optional landmark.
  final String? landmark;

  /// Optional contact phone.
  final String? phone;

  /// Latitude. Null when the backend did not provide coordinates.
  final double? lat;

  /// Longitude. Null when the backend did not provide coordinates.
  final double? lng;

  /// Lenient parser. Accepts both `lat`/`lng` and `latitude`/`longitude`
  /// field names, and both string and numeric coordinate values.
  ///
  /// Out-of-range coordinates trigger [InvalidCoordinateException]
  /// from the constructor — the parser does not silently clamp.
  factory DeliveryAddress.fromJson(Map<String, dynamic> j) {
    return DeliveryAddress(
      name: OrderParser.readString(j, 'name'),
      address: OrderParser.readString(j, 'address'),
      landmark: OrderParser.readStringOpt(j, 'landmark'),
      phone: OrderParser.readStringOpt(j, 'phone'),
      lat: OrderParser.readDoubleOpt(j, 'lat', 'latitude'),
      lng: OrderParser.readDoubleOpt(j, 'lng', 'longitude'),
    );
  }

  /// Serialises to camelCase JSON. Null fields are omitted.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'address': address,
    if (landmark != null) 'landmark': landmark,
    if (phone != null) 'phone': phone,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
  };

  /// Returns a copy with the supplied fields replaced.
  DeliveryAddress copyWith({
    String? name,
    String? address,
    String? landmark,
    String? phone,
    double? lat,
    double? lng,
  }) {
    return DeliveryAddress(
      name: name ?? this.name,
      address: address ?? this.address,
      landmark: landmark ?? this.landmark,
      phone: phone ?? this.phone,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DeliveryAddress &&
        other.name == name &&
        other.address == address &&
        other.landmark == landmark &&
        other.phone == phone &&
        other.lat == lat &&
        other.lng == lng;
  }

  @override
  int get hashCode => Object.hash(name, address, landmark, phone, lat, lng);

  @override
  String toString() =>
      'DeliveryAddress(name=$name, address=$address, lat=$lat, lng=$lng)';
}
