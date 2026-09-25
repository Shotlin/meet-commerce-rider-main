// Property 5 — Coordinate range invariants.
//
// For any (lat, lng) pair drawn from the real-number range, the parser
// path (`DeliveryAddress.fromJson`, `StoreInfo.fromJson`) and the
// constructor path (`DeliveryAddress(...)`, `StoreInfo(...)`,
// `Coordinate(...)`) agree:
//   - if lat ∈ [-90, 90] and lng ∈ [-180, 180], both paths succeed and
//     produce equal values,
//   - if either bound is violated, both paths throw
//     `InvalidCoordinateException` with the offending value in the
//     message.
//
// Validates: Requirements 28.3.

import 'package:glados/glados.dart';

import 'package:meet_commerce_rider_main/core/utils/coordinate.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/store_info.dart';

void main() {
  /// True when both dimensions fall inside the WGS-84 valid range.
  bool inRange(double lat, double lng) =>
      lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;

  // Feature: freashcut-rider, Property 5: Coordinate range invariants
  // hold in both parser and constructor paths
  Glados2<double, double>(any.double, any.double).test(
    'Coordinate range invariants hold in both parser and constructor paths',
    (double lat, double lng) {
      final bool valid = inRange(lat, lng);

      // -----------------------------------------------------------------
      // 1. Coordinate(double, double) — bare value object
      // -----------------------------------------------------------------
      if (valid) {
        final Coordinate coord = Coordinate(lat, lng);
        expect(coord.lat, lat);
        expect(coord.lng, lng);
      } else {
        Object? thrown;
        try {
          Coordinate(lat, lng);
        } catch (e) {
          thrown = e;
        }
        expect(thrown, isA<InvalidCoordinateException>());
        final InvalidCoordinateException ex =
            thrown! as InvalidCoordinateException;
        // The offending value must be captured both as a typed field
        // and inside the rendered message so logs surface the bad input.
        final bool latOut = lat < -90.0 || lat > 90.0;
        final double offending = latOut ? lat : lng;
        expect(ex.value, offending);
        expect(ex.toString(), contains(offending.toString()));
      }

      // -----------------------------------------------------------------
      // 2. DeliveryAddress — parser path AND constructor path
      // -----------------------------------------------------------------
      final Map<String, dynamic> addressJson = <String, dynamic>{
        'name': 'x',
        'address': 'y',
        'lat': lat,
        'lng': lng,
      };
      if (valid) {
        final DeliveryAddress fromJson = DeliveryAddress.fromJson(addressJson);
        final DeliveryAddress fromCtor = DeliveryAddress(
          name: 'x',
          address: 'y',
          lat: lat,
          lng: lng,
        );
        // Both paths succeed and produce equal values.
        expect(fromJson, equals(fromCtor));
        expect(fromJson.lat, lat);
        expect(fromJson.lng, lng);
      } else {
        expect(
          () => DeliveryAddress.fromJson(addressJson),
          throwsA(isA<InvalidCoordinateException>()),
        );
        expect(
          () => DeliveryAddress(name: 'x', address: 'y', lat: lat, lng: lng),
          throwsA(isA<InvalidCoordinateException>()),
        );
      }

      // -----------------------------------------------------------------
      // 3. StoreInfo — parser path AND constructor path
      // -----------------------------------------------------------------
      final Map<String, dynamic> storeJson = <String, dynamic>{
        'name': 'x',
        'address': 'y',
        'phone': '',
        'lat': lat,
        'lng': lng,
      };
      if (valid) {
        final StoreInfo fromJson = StoreInfo.fromJson(storeJson);
        final StoreInfo fromCtor = StoreInfo(
          name: 'x',
          address: 'y',
          phone: '',
          lat: lat,
          lng: lng,
        );
        expect(fromJson, equals(fromCtor));
        expect(fromJson.lat, lat);
        expect(fromJson.lng, lng);
      } else {
        expect(
          () => StoreInfo.fromJson(storeJson),
          throwsA(isA<InvalidCoordinateException>()),
        );
        expect(
          () =>
              StoreInfo(name: 'x', address: 'y', phone: '', lat: lat, lng: lng),
          throwsA(isA<InvalidCoordinateException>()),
        );
      }
    },
  );

  // Small unit test confirming the exception's message carries the
  // offending value (the property test relies on this fact, this test
  // documents it independently).
  group('InvalidCoordinateException', () {
    test('lat constructor records the offending value in toString()', () {
      const InvalidCoordinateException ex = InvalidCoordinateException.lat(
        123.0,
      );
      expect(ex.field, 'lat');
      expect(ex.value, 123.0);
      expect(ex.toString(), contains('lat'));
      expect(ex.toString(), contains('123.0'));
    });

    test('lng constructor records the offending value in toString()', () {
      const InvalidCoordinateException ex = InvalidCoordinateException.lng(
        -200.5,
      );
      expect(ex.field, 'lng');
      expect(ex.value, -200.5);
      expect(ex.toString(), contains('lng'));
      expect(ex.toString(), contains('-200.5'));
    });
  });
}
