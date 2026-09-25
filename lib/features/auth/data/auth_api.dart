import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../domain/auth_session.dart';

/// Thin transport-level wrapper around the live `/auth` endpoints.
///
/// `AuthApi` knows how to build and decode REST calls; it does NOT
/// translate failures into rider-specific exceptions (that's
/// [AuthRepository]'s job) and it does NOT touch persistent storage.
///
/// All paths are relative to [ApiClient.baseUrl] (which the bootstrap
/// pins to the configured Meet Commerce REST base).
class AuthApi {
  /// Wraps the supplied [client].
  AuthApi(this._client);

  final ApiClient _client;

  /// Sends a one-time password to [phone] in E.164 form.
  ///
  /// Returns the parsed `data` block. In dev environments the live
  /// backend echoes the OTP under `data.otp`; in production [otp] is
  /// absent. The repository layer is responsible for surfacing that
  /// to the UI only under the `dev` flavor.
  Future<SendOtpResult> sendOtp({required String phone}) async {
    final ApiEnvelope<SendOtpResult> envelope = await _client
        .post<SendOtpResult>(
          '/auth/send-otp',
          body: <String, dynamic>{'phone': phone},
          parseData: SendOtpResult._parse,
        );
    return envelope.data ?? const SendOtpResult();
  }

  /// Verifies the entered OTP and returns a fresh [AuthSession].
  ///
  /// Always sends `role: 'RIDER'` per the rider-app contract; the
  /// backend canonicalizes any aliases internally.
  Future<AuthSession> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final ApiEnvelope<AuthSession> envelope = await _client.post<AuthSession>(
      '/auth/verify-otp',
      body: <String, dynamic>{'phone': phone, 'otp': otp, 'role': 'RIDER'},
      parseData: (Object? raw) =>
          AuthSession.fromVerifyJson(_asMap(raw, 'verify-otp')),
    );
    final AuthSession? session = envelope.data;
    if (session == null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/auth/verify-otp'),
        type: DioExceptionType.badResponse,
        message: 'verify-otp returned no session',
      );
    }
    return session;
  }

  /// Exchanges a refresh token for a fresh access/refresh pair.
  ///
  /// The live backend rotates BOTH tokens on every refresh, so the
  /// caller must persist whichever pair this returns.
  Future<RefreshTokenResult> refreshToken({
    required String refreshToken,
  }) async {
    final ApiEnvelope<RefreshTokenResult> envelope = await _client
        .post<RefreshTokenResult>(
          '/auth/refresh-token',
          body: <String, dynamic>{'refreshToken': refreshToken},
          parseData: (Object? raw) =>
              RefreshTokenResult._fromJson(_asMap(raw, 'refresh-token')),
        );
    final RefreshTokenResult? result = envelope.data;
    if (result == null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/auth/refresh-token'),
        type: DioExceptionType.badResponse,
        message: 'refresh-token returned no tokens',
      );
    }
    return result;
  }

  /// Logs the rider out on the backend. The local session must be
  /// cleared by the caller regardless of whether this call succeeds.
  Future<void> logout() async {
    await _client.post<Object?>(
      '/auth/logout',
      parseData: (Object? raw) => raw,
    );
  }

  static Map<String, dynamic> _asMap(Object? raw, String routeName) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    throw DioException(
      requestOptions: RequestOptions(path: '/auth/$routeName'),
      type: DioExceptionType.badResponse,
      message: '$routeName returned malformed payload: $raw',
    );
  }
}

/// Result of `/auth/send-otp`.
class SendOtpResult {
  /// Constructs an empty result (production responses omit `otp`).
  const SendOtpResult({this.devOtp});

  /// Dev-only OTP echoed by the backend under `data.otp`. Null in
  /// production or whenever the backend omits the field.
  final String? devOtp;

  static SendOtpResult _parse(Object? raw) {
    if (raw is Map) {
      final Object? otp = raw['otp'];
      if (otp is String && otp.isNotEmpty) {
        return SendOtpResult(devOtp: otp);
      }
    }
    return const SendOtpResult();
  }
}

/// Result of `/auth/refresh-token`.
class RefreshTokenResult {
  /// Constructs a refresh result explicitly.
  const RefreshTokenResult({
    required this.accessToken,
    required this.refreshToken,
  });

  /// New short-lived access JWT.
  final String accessToken;

  /// New long-lived refresh JWT (the backend rotates this on every call).
  final String refreshToken;

  static RefreshTokenResult _fromJson(Map<String, dynamic> json) {
    return RefreshTokenResult(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
    );
  }
}
