import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/features/auth/domain/auth_session.dart';
import 'package:meet_commerce_rider_main/features/auth/domain/rider_user.dart';

void main() {
  group('RiderUser.fromJson', () {
    test('parses the live verify-otp shape (camelCase)', () {
      final RiderUser user = RiderUser.fromJson(<String, dynamic>{
        'id': '3fbc4c74-8526-4003-9f00-48a3538b7637',
        'phone': '9999999999',
        'name': 'Priya Nair',
        'role': 'RIDER',
        'isNewUser': false,
        'isVerified': false,
      });

      expect(user.id, '3fbc4c74-8526-4003-9f00-48a3538b7637');
      expect(user.phone, '9999999999');
      expect(user.name, 'Priya Nair');
      expect(user.role, 'RIDER');
      expect(user.isNewUser, isFalse);
      expect(user.isVerified, isFalse);
      expect(user.isRider, isTrue);
      expect(user.e164Phone, '+919999999999');
    });

    test('accepts snake_case fallbacks', () {
      final RiderUser user = RiderUser.fromJson(<String, dynamic>{
        'id': 'u',
        'phone': '9999999999',
        'role': 'RIDER',
        'is_new_user': true,
        'is_verified': true,
      });

      expect(user.isNewUser, isTrue);
      expect(user.isVerified, isTrue);
    });

    test('treats role mismatch via isRider', () {
      final RiderUser user = RiderUser.fromJson(<String, dynamic>{
        'id': 'u',
        'phone': '9876543210',
        'role': 'CUSTOMER',
        'isNewUser': false,
        'isVerified': true,
      });

      expect(user.isRider, isFalse);
    });

    test('e164Phone preserves an already-prefixed input', () {
      final RiderUser user = RiderUser.fromJson(<String, dynamic>{
        'id': 'u',
        'phone': '+919999999999',
        'role': 'RIDER',
        'isNewUser': false,
        'isVerified': false,
      });
      expect(user.e164Phone, '+919999999999');
    });
  });

  group('AuthSession.fromVerifyJson', () {
    test('parses the live verify-otp data block end-to-end', () {
      final AuthSession session = AuthSession.fromVerifyJson(<String, dynamic>{
        'accessToken': 'A',
        'refreshToken': 'R',
        'user': <String, dynamic>{
          'id': 'u',
          'phone': '9999999999',
          'name': 'Priya',
          'role': 'RIDER',
          'isNewUser': false,
          'isVerified': false,
        },
      });

      expect(session.accessToken, 'A');
      expect(session.refreshToken, 'R');
      expect(session.user.id, 'u');
      expect(session.user.role, 'RIDER');
    });

    test('throws when the user object is missing', () {
      expect(
        () => AuthSession.fromVerifyJson(<String, dynamic>{
          'accessToken': 'A',
          'refreshToken': 'R',
        }),
        throwsFormatException,
      );
    });

    test('copyWithTokens replaces just the tokens', () {
      final AuthSession session = AuthSession.fromVerifyJson(<String, dynamic>{
        'accessToken': 'A',
        'refreshToken': 'R',
        'user': <String, dynamic>{
          'id': 'u',
          'phone': '9999999999',
          'role': 'RIDER',
          'isNewUser': false,
          'isVerified': false,
        },
      });
      final AuthSession refreshed = session.copyWithTokens(
        accessToken: 'A2',
        refreshToken: 'R2',
      );
      expect(refreshed.accessToken, 'A2');
      expect(refreshed.refreshToken, 'R2');
      expect(refreshed.user, session.user);
    });
  });
}
