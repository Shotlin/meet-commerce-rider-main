import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_token_store.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/auth_exception.dart';
import '../domain/auth_session.dart';
import '../domain/rider_user.dart';
import 'auth_api.dart';

/// Coordinates `AuthApi` with `SecureTokenStore` and translates the
/// transport-level [ApiException] hierarchy into the rider-specific
/// [AuthException] family the UI layer pattern-matches on.
///
/// Responsibilities:
/// - Validate phone numbers client-side before hitting the backend.
/// - Persist the access + refresh tokens after a successful sign-in /
///   refresh.
/// - Treat a non-`RIDER` user role as a sign-in failure (clears the
///   tokens we may have just persisted and throws
///   [AuthRoleNotAllowedException]).
/// - Always clear local tokens on logout, even when the network call
///   fails — logout must succeed locally.
class AuthRepository {
  /// Wires the repository to its dependencies.
  AuthRepository({required AuthApi api, required SecureTokenStore tokenStore})
    : _api = api,
      _tokenStore = tokenStore;

  final AuthApi _api;
  final SecureTokenStore _tokenStore;

  /// Validates a phone number entered on the login screen.
  ///
  /// The live backend wants a 10-digit Indian mobile number prefixed
  /// with `+91`. We accept either form on entry and canonicalize to
  /// E.164 here; values that can't be canonicalized throw
  /// [AuthInvalidPhoneException] without hitting the network.
  static String canonicalizePhone(String input) {
    final String trimmed = input.trim().replaceAll(RegExp(r'\s+'), '');
    if (trimmed.isEmpty) {
      throw const AuthInvalidPhoneException();
    }
    String digits;
    if (trimmed.startsWith('+91')) {
      digits = trimmed.substring(3);
    } else if (trimmed.startsWith('91') && trimmed.length == 12) {
      digits = trimmed.substring(2);
    } else if (trimmed.startsWith('+')) {
      throw const AuthInvalidPhoneException();
    } else {
      digits = trimmed;
    }
    if (digits.length != 10 || !RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      throw const AuthInvalidPhoneException();
    }
    return '+91$digits';
  }

  /// Sends a one-time password to [rawPhone] (any reasonable format).
  ///
  /// Returns the [SendOtpResult] including the dev-only echoed OTP. The
  /// presentation layer surfaces the dev OTP only under the `dev` flavor.
  Future<SendOtpResult> sendOtp(String rawPhone) async {
    final String phone = canonicalizePhone(rawPhone);
    try {
      final SendOtpResult result = await _api.sendOtp(phone: phone);
      AppLogger.info(LogTopic.auth, 'send-otp ok phone=$phone');
      return result;
    } on ApiException catch (error) {
      throw _mapApiException(error);
    }
  }

  /// Verifies [otp] for [rawPhone] and persists the resulting tokens.
  ///
  /// Throws:
  /// - [AuthInvalidPhoneException] if [rawPhone] fails client-side validation.
  /// - [AuthInvalidOtpException] for backend `INVALID_OTP`.
  /// - [AuthRateLimitedException] for HTTP 429.
  /// - [AuthRoleNotAllowedException] if the resulting user is not a rider.
  /// - [AuthUnexpectedException] for anything else.
  Future<AuthSession> verifyOtp({
    required String rawPhone,
    required String otp,
  }) async {
    final String phone = canonicalizePhone(rawPhone);
    AuthSession session;
    try {
      session = await _api.verifyOtp(phone: phone, otp: otp);
    } on ApiException catch (error) {
      throw _mapApiException(error);
    }

    // Persist tokens BEFORE the role check so that if we end up clearing
    // them again it's an explicit revoke rather than a partial state.
    await _tokenStore.writeTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );

    final RiderUser user = session.user;
    if (!user.isRider) {
      AppLogger.warn(
        LogTopic.auth,
        'verify-otp succeeded but role=${user.role} != RIDER; '
        'clearing local session',
      );
      await _tokenStore.clear();
      throw const AuthRoleNotAllowedException();
    }

    AppLogger.info(
      LogTopic.auth,
      'verify-otp ok user=${user.id} role=${user.role}',
    );
    return session;
  }

  /// Exchanges the persisted refresh token for a new access/refresh pair.
  ///
  /// Returns `false` when the refresh fails for any reason (network,
  /// 401, malformed body); the caller — typically the auth interceptor —
  /// then leaves the session as-is and surfaces the failure.
  ///
  /// On success, both tokens are written to the [SecureTokenStore]
  /// before returning so that the next request to the API client picks
  /// up the new access token automatically.
  ///
  /// Only a confirmed rejection (the backend explicitly says this
  /// refresh token is invalid/expired — [ApiAuthException]) clears the
  /// token store here. A transient failure (timeout, offline, 5xx)
  /// deliberately leaves the existing refresh token in place: it may
  /// still be perfectly valid, and callers must not treat "the refresh
  /// call failed" as proof the session is dead — see
  /// [SessionController.restore] which checks [SecureTokenStore] to
  /// tell the two cases apart before deciding to log the rider out.
  Future<bool> refreshTokens() async {
    final String? refresh = await _tokenStore.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final RefreshTokenResult result = await _api.refreshToken(
        refreshToken: refresh,
      );
      await _tokenStore.writeTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      AppLogger.info(LogTopic.auth, 'refresh-token ok');
      return true;
    } on ApiAuthException catch (error, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'refresh-token rejected: ${error.message}',
        error: error,
        stackTrace: stack,
      );
      // The backend confirmed this refresh token is actually dead
      // (expired, revoked, or superseded by a login elsewhere) — no
      // amount of retrying fixes this, so clear it now.
      await _tokenStore.clear();
      return false;
    } on ApiException catch (error, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'refresh-token failed transiently: ${error.message}',
        error: error,
        stackTrace: stack,
      );
      // Network/timeout/server error — we have no evidence the refresh
      // token itself is bad, so leave it in storage for the rider's
      // next retry instead of forcing a false logout over a blip.
      return false;
    }
  }

  /// Logs the rider out: hits the backend, then clears local tokens.
  ///
  /// Local clear is unconditional. If the backend call fails we log
  /// the error but still complete logout — the local session is the
  /// authoritative thing to clean up because the rider asked for it.
  Future<void> logout() async {
    try {
      await _api.logout();
    } on ApiException catch (error, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'logout backend call failed (proceeding with local clear)',
        error: error,
        stackTrace: stack,
      );
    } finally {
      await _tokenStore.clear();
    }
  }

  /// Maps a transport-level [ApiException] onto the most specific
  /// [AuthException]. Backend codes win when present; otherwise we fall
  /// back to status-based heuristics.
  AuthException _mapApiException(ApiException error) {
    final String code = error.backendCode ?? '';
    if (code == 'INVALID_OTP') {
      return AuthInvalidOtpException(
        error.message.isEmpty ? 'OTP did not match. Try again' : error.message,
      );
    }
    if (code == 'INVALID_PHONE') {
      return AuthInvalidPhoneException(
        error.message.isEmpty
            ? 'Enter a valid phone number with country code'
            : error.message,
      );
    }
    if (error.statusCode == 429) {
      return AuthRateLimitedException(
        message: error.message.isEmpty
            ? 'Too many attempts. Please wait a moment'
            : error.message,
        cause: error,
      );
    }
    return AuthUnexpectedException(
      error.message.isEmpty ? 'Authentication failed' : error.message,
      cause: error,
    );
  }
}
