import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/order_parse_exception.dart';

void main() {
  group('DeliveryAddress.fromJson', () {
    test('parses valid address with lat/lng as numbers', () {
      final DeliveryAddress addr = DeliveryAddress.fromJson(<String, dynamic>{
        'name': 'FreshCuts Store',
        'address': '123 Main St',
        'landmark': 'Near park',
        'phone': '9999999999',
        'lat': 22.5726,
        'lng': 88.3639,
      });

      expect(addr.name, 'FreshCuts Store');
      expect(addr.address, '123 Main St');
      expect(addr.landmark, 'Near park');
      expect(addr.phone, '9999999999');
      expect(addr.lat, closeTo(22.5726, 0.0001));
      expect(addr.lng, closeTo(88.3639, 0.0001));
    });

    test('accepts latitude/longitude field names as fallback', () {
      final DeliveryAddress addr = DeliveryAddress.fromJson(<String, dynamic>{
        'name': 'Customer',
        'address': '456 Side St',
        'latitude': 22.5726,
        'longitude': 88.3639,
      });

      expect(addr.lat, closeTo(22.5726, 0.0001));
      expect(addr.lng, closeTo(88.3639, 0.0001));
    });

    test('accepts string coordinates (live profile shape)', () {
      final DeliveryAddress addr = DeliveryAddress.fromJson(<String, dynamic>{
        'name': 'Rider',
        'address': 'Kolkata',
        'lat': '22.57260000',
        'lng': '88.36390000',
      });

      expect(addr.lat, closeTo(22.5726, 0.0001));
      expect(addr.lng, closeTo(88.3639, 0.0001));
    });

    test('allows null coordinates', () {
      final DeliveryAddress addr = DeliveryAddress.fromJson(<String, dynamic>{
        'name': 'Store',
        'address': 'Unknown',
      });

      expect(addr.lat, isNull);
      expect(addr.lng, isNull);
    });

    test('round-trips through toJson/fromJson', () {
      final DeliveryAddress original = DeliveryAddress(
        name: 'Test',
        address: '1 Test Rd',
        landmark: 'Near test',
        phone: '9876543210',
        lat: 12.9716,
        lng: 77.5946,
      );

      final DeliveryAddress roundTripped = DeliveryAddress.fromJson(
        original.toJson(),
      );

      expect(roundTripped, equals(original));
    });
  });

  group('DeliveryAddress coordinate validation', () {
    test('throws InvalidCoordinateException for lat > 90', () {
      expect(
        () => DeliveryAddress(name: 'Bad', address: 'Bad', lat: 91.0, lng: 0.0),
        throwsA(isA<InvalidCoordinateException>()),
      );
    });

    test('throws InvalidCoordinateException for lat < -90', () {
      expect(
        () =>
            DeliveryAddress(name: 'Bad', address: 'Bad', lat: -91.0, lng: 0.0),
        throwsA(isA<InvalidCoordinateException>()),
      );
    });

    test('throws InvalidCoordinateException for lng > 180', () {
      expect(
        () =>
            DeliveryAddress(name: 'Bad', address: 'Bad', lat: 0.0, lng: 181.0),
        throwsA(isA<InvalidCoordinateException>()),
      );
    });

    test('throws InvalidCoordinateException for lng < -180', () {
      expect(
        () =>
            DeliveryAddress(name: 'Bad', address: 'Bad', lat: 0.0, lng: -181.0),
        throwsA(isA<InvalidCoordinateException>()),
      );
    });

    test('accepts boundary values lat=90, lng=180', () {
      final DeliveryAddress addr = DeliveryAddress(
        name: 'Edge',
        address: 'Edge',
        lat: 90.0,
        lng: 180.0,
      );
      expect(addr.lat, 90.0);
      expect(addr.lng, 180.0);
    });

    test('accepts boundary values lat=-90, lng=-180', () {
      final DeliveryAddress addr = DeliveryAddress(
        name: 'Edge',
        address: 'Edge',
        lat: -90.0,
        lng: -180.0,
      );
      expect(addr.lat, -90.0);
      expect(addr.lng, -180.0);
    });

    test(
      'fromJson with out-of-range lat throws InvalidCoordinateException',
      () {
        expect(
          () => DeliveryAddress.fromJson(<String, dynamic>{
            'name': 'Bad',
            'address': 'Bad',
            'lat': 200.0,
            'lng': 0.0,
          }),
          throwsA(isA<InvalidCoordinateException>()),
        );
      },
    );

    test(
      'fromJson with out-of-range lng throws InvalidCoordinateException',
      () {
        expect(
          () => DeliveryAddress.fromJson(<String, dynamic>{
            'name': 'Bad',
            'address': 'Bad',
            'lat': 0.0,
            'lng': -200.0,
          }),
          throwsA(isA<InvalidCoordinateException>()),
        );
      },
    );

    test('fromJson with string out-of-range lat throws', () {
      expect(
        () => DeliveryAddress.fromJson(<String, dynamic>{
          'name': 'Bad',
          'address': 'Bad',
          'lat': '95.0',
          'lng': '0.0',
        }),
        throwsA(isA<InvalidCoordinateException>()),
      );
    });
  });

  group('DeliveryAddress equality', () {
    test('two identical addresses are equal', () {
      final DeliveryAddress a = DeliveryAddress(
        name: 'Store',
        address: '1 Main St',
        lat: 22.5726,
        lng: 88.3639,
      );
      final DeliveryAddress b = DeliveryAddress(
        name: 'Store',
        address: '1 Main St',
        lat: 22.5726,
        lng: 88.3639,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
