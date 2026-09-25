import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';

/// Domain-level exceptions raised by [AuthRepository] / [AuthApi].
///
/// These wrap the lower-level [ApiException] hierarchy so the
/// presentation layer can pattern-match on rider-specific failure modes
/// (`Invalid OTP`, `Phone not allowed`, `This account is not enabled
/// for the rider app`) without having to read backend codes inline.
@immutable
sealed class AuthException implements Exception {
  /// Constructs an auth exception with the user-facing [message] and
  /// the underlying transport [cause].
  const AuthException(this.message, {this.cause});

  /// Human-readable copy used by the presentation layer.
  final String message;

  /// Underlying transport / API exception when the failure originated
  /// from the network layer.
  final ApiException? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Phone number failed client-side or server-side validation.
final class AuthInvalidPhoneException extends AuthException {
  /// Constructs the exception with [message] (defaults to the live
  /// backend's `INVALID_PHONE` copy).
  const AuthInvalidPhoneException([
    String message = 'Enter a valid phone number with country code',
  ]) : super(message);
}

/// OTP failed validation (wrong code, expired, or malformed).
final class AuthInvalidOtpException extends AuthException {
  /// Constructs the exception with [message] (defaults to the live
  /// backend's `INVALID_OTP` copy).
  const AuthInvalidOtpException([
    String message = 'OTP did not match. Try again',
  ]) : super(message);
}

/// Backend rate-limited the auth route. The `retryAfter` advises the
/// UI how long to wait before re-enabling the resend control.
final class AuthRateLimitedException extends AuthException {
  /// Constructs a rate-limit exception with optional [retryAfter].
  const AuthRateLimitedException({
    String message = 'Too many attempts. Please wait a moment',
    this.retryAfter,
    super.cause,
  }) : super(message);

  /// Suggested wait before retrying. Reflects the `Retry-After` header.
  final Duration? retryAfter;
}

/// Account exists but is not allowed in the rider app (role mismatch).
final class AuthRoleNotAllowedException extends AuthException {
  /// Constructs the role-mismatch exception with the standard rider
  /// app copy.
  const AuthRoleNotAllowedException()
    : super('This account is not enabled for the rider app');
}

/// Catch-all for anything that wasn't classified more specifically.
final class AuthUnexpectedException extends AuthException {
  /// Wraps an [ApiException] with a generic message.
  const AuthUnexpectedException(super.message, {super.cause});
}
