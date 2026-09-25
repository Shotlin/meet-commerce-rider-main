import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/core/network/api_exception.dart';
import 'package:meet_commerce_rider_main/core/storage/secure_token_store.dart';
import 'package:meet_commerce_rider_main/features/auth/data/auth_api.dart';
import 'package:meet_commerce_rider_main/features/auth/data/auth_repository.dart';
import 'package:meet_commerce_rider_main/features/auth/domain/auth_exception.dart';
import 'package:meet_commerce_rider_main/features/auth/domain/auth_session.dart';
import 'package:meet_commerce_rider_main/features/auth/domain/rider_user.dart';

class _MockAuthApi extends Mock implements AuthApi {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('AuthRepository.canonicalizePhone', () {
    test('accepts a 10-digit Indian mobile number', () {
      expect(AuthRepository.canonicalizePhone('9876543210'), '+919876543210');
    });

    test('accepts +91 prefixed input', () {
      expect(
        AuthRepository.canonicalizePhone('+919876543210'),
        '+919876543210',
      );
    });

    test('accepts 91-prefixed (no plus) input', () {
      expect(AuthRepository.canonicalizePhone('919876543210'), '+919876543210');
    });

    test('strips whitespace inside and around the input', () {
      expect(
        AuthRepository.canonicalizePhone('  98 76 5432 10 '),
        '+919876543210',
      );
    });

    test('rejects too-short numbers', () {
      expect(
        () => AuthRepository.canonicalizePhone('12345'),
        throwsA(isA<AuthInvalidPhoneException>()),
      );
    });

    test('rejects numbers starting with non-mobile leading digit', () {
      expect(
        () => AuthRepository.canonicalizePhone('1234567890'),
        throwsA(isA<AuthInvalidPhoneException>()),
      );
    });

    test('rejects empty input', () {
      expect(
        () => AuthRepository.canonicalizePhone(''),
        throwsA(isA<AuthInvalidPhoneException>()),
      );
    });

    test('rejects non-Indian +country codes', () {
      expect(
        () => AuthRepository.canonicalizePhone('+11234567890'),
        throwsA(isA<AuthInvalidPhoneException>()),
      );
    });
  });

  group('AuthRepository.sendOtp', () {
    test('canonicalizes phone before hitting the API', () async {
      final _MockAuthApi api = _MockAuthApi();
      when(
        () => api.sendOtp(phone: any(named: 'phone')),
      ).thenAnswer((_) async => const SendOtpResult());

      final AuthRepository repo = AuthRepository(
        api: api,
        tokenStore: InMemoryTokenStore(),
      );

      await repo.sendOtp('9876543210');

      verify(() => api.sendOtp(phone: '+919876543210')).called(1);
    });

    test('translates INVALID_PHONE into AuthInvalidPhoneException', () async {
      final _MockAuthApi api = _MockAuthApi();
      when(() => api.sendOtp(phone: any(named: 'phone'))).thenThrow(
        const ApiValidationException(
          'Invalid phone number',
          statusCode: 422,
          backendCode: 'INVALID_PHONE',
        ),
      );

      final AuthRepository repo = AuthRepository(
        api: api,
        tokenStore: InMemoryTokenStore(),
      );

      await expectLater(
        () => repo.sendOtp('+919876543210'),
        throwsA(isA<AuthInvalidPhoneException>()),
      );
    });

    test('rate-limit (429) becomes AuthRateLimitedException', () async {
      final _MockAuthApi api = _MockAuthApi();
      when(() => api.sendOtp(phone: any(named: 'phone'))).thenThrow(
        const ApiValidationException('Too many requests', statusCode: 429),
      );

      final AuthRepository repo = AuthRepository(
        api: api,
        tokenStore: InMemoryTokenStore(),
      );

      await expectLater(
        () => repo.sendOtp('+919876543210'),
        throwsA(isA<AuthRateLimitedException>()),
      );
    });
  });

  group('AuthRepository.verifyOtp', () {
    test('persists tokens and returns session on success', () async {
      final _MockAuthApi api = _MockAuthApi();
      const RiderUser user = RiderUser(
        id: 'u1',
        phone: '9876543210',
        role: 'RIDER',
        isNewUser: false,
        isVerified: false,
      );
      const AuthSession session = AuthSession(
        accessToken: 'A',
        refreshToken: 'R',
        user: user,
      );
      when(
        () => api.verifyOtp(
          phone: any(named: 'phone'),
          otp: any(named: 'otp'),
        ),
      ).thenAnswer((_) async => session);

      final SecureTokenStore store = InMemoryTokenStore();
      final AuthRepository repo = AuthRepository(api: api, tokenStore: store);

      final AuthSession result = await repo.verifyOtp(
        rawPhone: '9876543210',
        otp: '123456',
      );

      expect(result, session);
      expect(await store.readAccessToken(), 'A');
      expect(await store.readRefreshToken(), 'R');
    });

    test('clears tokens and throws when the user is not a rider', () async {
      final _MockAuthApi api = _MockAuthApi();
      const RiderUser customer = RiderUser(
        id: 'u1',
        phone: '9876543210',
        role: 'CUSTOMER',
        isNewUser: false,
        isVerified: true,
      );
      const AuthSession session = AuthSession(
        accessToken: 'A',
        refreshToken: 'R',
        user: customer,
      );
      when(
        () => api.verifyOtp(
          phone: any(named: 'phone'),
          otp: any(named: 'otp'),
        ),
      ).thenAnswer((_) async => session);

      final SecureTokenStore store = InMemoryTokenStore();
      final AuthRepository repo = AuthRepository(api: api, tokenStore: store);

      await expectLater(
        () => repo.verifyOtp(rawPhone: '9876543210', otp: '123456'),
        throwsA(isA<AuthRoleNotAllowedException>()),
      );

      // Tokens written, then cleared.
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('translates INVALID_OTP into AuthInvalidOtpException', () async {
      final _MockAuthApi api = _MockAuthApi();
      when(
        () => api.verifyOtp(
          phone: any(named: 'phone'),
          otp: any(named: 'otp'),
        ),
      ).thenThrow(
        const ApiValidationException(
          'Invalid OTP',
          statusCode: 422,
          backendCode: 'INVALID_OTP',
        ),
      );

      final SecureTokenStore store = InMemoryTokenStore();
      final AuthRepository repo = AuthRepository(api: api, tokenStore: store);

      await expectLater(
        () => repo.verifyOtp(rawPhone: '9876543210', otp: '000000'),
        throwsA(isA<AuthInvalidOtpException>()),
      );

      // No tokens written.
      expect(await store.readAccessToken(), isNull);
    });
  });

  group('AuthRepository.refreshTokens', () {
    test('returns false when no refresh token is stored', () async {
      final _MockAuthApi api = _MockAuthApi();
      final AuthRepository repo = AuthRepository(
        api: api,
        tokenStore: InMemoryTokenStore(),
      );
      expect(await repo.refreshTokens(), isFalse);
      verifyNever(
        () => api.refreshToken(refreshToken: any(named: 'refreshToken')),
      );
    });

    test('writes both new tokens on success', () async {
      final _MockAuthApi api = _MockAuthApi();
      when(
        () => api.refreshToken(refreshToken: any(named: 'refreshToken')),
      ).thenAnswer(
        (_) async =>
            const RefreshTokenResult(accessToken: 'A2', refreshToken: 'R2'),
      );
      final SecureTokenStore store = InMemoryTokenStore(
        accessToken: 'A1',
        refreshToken: 'R1',
      );
      final AuthRepository repo = AuthRepository(api: api, tokenStore: store);

      expect(await repo.refreshTokens(), isTrue);
      expect(await store.readAccessToken(), 'A2');
      expect(await store.readRefreshToken(), 'R2');
    });

    test(
      'returns false on transport failure (does not clear the store)',
      () async {
        final _MockAuthApi api = _MockAuthApi();
        when(
          () => api.refreshToken(refreshToken: any(named: 'refreshToken')),
        ).thenThrow(const ApiTimeoutException('slow'));
        final SecureTokenStore store = InMemoryTokenStore(
          accessToken: 'A',
          refreshToken: 'R',
        );
        final AuthRepository repo = AuthRepository(api: api, tokenStore: store);

        expect(await repo.refreshTokens(), isFalse);
        // We deliberately do NOT clear on transient failure; it's the
        // caller's job to decide.
        expect(await store.readAccessToken(), 'A');
        expect(await store.readRefreshToken(), 'R');
      },
    );

    test(
      'clears the store when the backend confirms the token is dead',
      () async {
        final _MockAuthApi api = _MockAuthApi();
        when(
          () => api.refreshToken(refreshToken: any(named: 'refreshToken')),
        ).thenThrow(const ApiAuthException('refresh token expired'));
        final SecureTokenStore store = InMemoryTokenStore(
          accessToken: 'A',
          refreshToken: 'R',
        );
        final AuthRepository repo = AuthRepository(api: api, tokenStore: store);

        expect(await repo.refreshTokens(), isFalse);
        // A confirmed rejection (401/403 from the refresh endpoint itself)
        // means the token really is dead, so this — and only this — case
        // clears it locally too.
        expect(await store.readAccessToken(), isNull);
        expect(await store.readRefreshToken(), isNull);
      },
    );
  });

  group('AuthRepository.logout', () {
    test('clears local session even when the backend call fails', () async {
      final _MockAuthApi api = _MockAuthApi();
      when(() => api.logout()).thenThrow(const ApiServerException('500'));

      final SecureTokenStore store = InMemoryTokenStore(
        accessToken: 'A',
        refreshToken: 'R',
      );
      final AuthRepository repo = AuthRepository(api: api, tokenStore: store);

      await repo.logout();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('clears local session on a successful backend logout too', () async {
      final _MockAuthApi api = _MockAuthApi();
      when(() => api.logout()).thenAnswer((_) async {});

      final SecureTokenStore store = InMemoryTokenStore(
        accessToken: 'A',
        refreshToken: 'R',
      );
      final AuthRepository repo = AuthRepository(api: api, tokenStore: store);

      await repo.logout();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });
  });
}
