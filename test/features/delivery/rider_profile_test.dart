import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_profile.dart';

/// The exact live profile JSON shape from the backend contract.
const Map<String, dynamic> _liveProfileJson = <String, dynamic>{
  'id': '9c598280-1234-5678-abcd-ef0123456789',
  'user_id': '3fbc4c74-8526-4003-9f00-48a3538b7637',
  'vehicle_type': null,
  'vehicle_number': null,
  'license_url': null,
  'aadhar_url': null,
  'is_approved': false,
  'is_online': false,
  'current_lat': '22.57260000',
  'current_lng': '88.36390000',
  'rating': '0.00',
  'total_deliveries': 0,
  'created_at': '2026-05-15T10:00:00.000Z',
  'updated_at': '2026-05-15T10:00:00.000Z',
  'commission_rate': '15.00',
  'bank_account_number': null,
  'bank_ifsc': null,
  'bank_name': null,
  'name': 'Priya Nair',
  'phone': '9999999999',
  'avatar_url': null,
};

void main() {
  group('RiderProfile.fromJson — live snake_case shape', () {
    test('parses the exact live profile JSON', () {
      final RiderProfile profile = RiderProfile.fromJson(_liveProfileJson);

      expect(profile.id, '9c598280-1234-5678-abcd-ef0123456789');
      expect(profile.userId, '3fbc4c74-8526-4003-9f00-48a3538b7637');
      expect(profile.vehicleType, isNull);
      expect(profile.vehicleNumber, isNull);
      expect(profile.isApproved, isFalse);
      expect(profile.isOnline, isFalse);
      expect(profile.currentLat, closeTo(22.5726, 0.0001));
      expect(profile.currentLng, closeTo(88.3639, 0.0001));
      expect(profile.rating, closeTo(0.0, 0.001));
      expect(profile.totalDeliveries, 0);
      expect(profile.commissionRate, closeTo(15.0, 0.001));
      expect(profile.bankAccountNumber, isNull);
      expect(profile.bankIfsc, isNull);
      expect(profile.bankName, isNull);
      expect(profile.name, 'Priya Nair');
      expect(profile.phone, '9999999999');
      expect(profile.avatarUrl, isNull);
    });

    test('parses string-typed numeric fields correctly', () {
      final RiderProfile profile = RiderProfile.fromJson(<String, dynamic>{
        'id': 'p1',
        'user_id': 'u1',
        'is_approved': false,
        'is_online': false,
        'rating': '4.75',
        'total_deliveries': 100,
        'commission_rate': '12.50',
        'current_lat': '13.08268000',
        'current_lng': '80.27071000',
      });

      expect(profile.rating, closeTo(4.75, 0.001));
      expect(profile.commissionRate, closeTo(12.50, 0.001));
      expect(profile.currentLat, closeTo(13.08268, 0.0001));
      expect(profile.currentLng, closeTo(80.27071, 0.0001));
    });

    test('accepts camelCase field names as fallback', () {
      final RiderProfile profile = RiderProfile.fromJson(<String, dynamic>{
        'id': 'p2',
        'userId': 'u2',
        'isApproved': true,
        'isOnline': true,
        'rating': 3.5,
        'totalDeliveries': 50,
        'commissionRate': 10.0,
        'currentLat': 22.5726,
        'currentLng': 88.3639,
      });

      expect(profile.userId, 'u2');
      expect(profile.isApproved, isTrue);
      expect(profile.isOnline, isTrue);
      expect(profile.rating, closeTo(3.5, 0.001));
      expect(profile.totalDeliveries, 50);
      expect(profile.commissionRate, closeTo(10.0, 0.001));
    });

    test('handles null current_lat/current_lng', () {
      final RiderProfile profile = RiderProfile.fromJson(<String, dynamic>{
        'id': 'p3',
        'user_id': 'u3',
        'is_approved': false,
        'is_online': false,
        'current_lat': null,
        'current_lng': null,
        'rating': '0.00',
        'total_deliveries': 0,
        'commission_rate': '15.00',
      });

      expect(profile.currentLat, isNull);
      expect(profile.currentLng, isNull);
    });

    test('isApproved is the authoritative approval flag', () {
      final RiderProfile approved = RiderProfile.fromJson(<String, dynamic>{
        'id': 'p4',
        'user_id': 'u4',
        'is_approved': true,
        'is_online': false,
        'rating': '0.00',
        'total_deliveries': 0,
        'commission_rate': '15.00',
      });

      final RiderProfile notApproved = RiderProfile.fromJson(<String, dynamic>{
        'id': 'p5',
        'user_id': 'u5',
        'is_approved': false,
        'is_online': false,
        'rating': '0.00',
        'total_deliveries': 0,
        'commission_rate': '15.00',
      });

      expect(approved.isApproved, isTrue);
      expect(notApproved.isApproved, isFalse);
    });

    test('round-trips through toJson/fromJson', () {
      final RiderProfile original = RiderProfile.fromJson(_liveProfileJson);
      final RiderProfile roundTripped = RiderProfile.fromJson(
        original.toJson(),
      );

      expect(roundTripped, equals(original));
    });

    test('copyWith replaces only specified fields', () {
      final RiderProfile original = RiderProfile.fromJson(_liveProfileJson);
      final RiderProfile updated = original.copyWith(
        isOnline: true,
        currentLat: 22.5800,
      );

      expect(updated.isOnline, isTrue);
      expect(updated.currentLat, closeTo(22.5800, 0.0001));
      expect(updated.id, original.id);
      expect(updated.rating, original.rating);
    });
  });
}
