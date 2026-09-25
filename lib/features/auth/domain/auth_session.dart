import 'package:flutter/foundation.dart';

import 'rider_user.dart';

/// Snapshot of a successful sign-in / token refresh.
///
/// Holds the access + refresh JWTs and the user record returned by
/// `/auth/verify-otp` (or just the new tokens after `/auth/refresh-token`,
/// which does not re-emit the user object — in that case [user] carries
/// the previous user record).
@immutable
class AuthSession {
  /// Constructs a session snapshot explicitly.
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  /// Builds a session from the data block of `/auth/verify-otp`:
  ///
  /// ```json
  /// {
  ///   "accessToken": "...",
  ///   "refreshToken": "...",
  ///   "user": { ... }
  /// }
  /// ```
  factory AuthSession.fromVerifyJson(Map<String, dynamic> json) {
    final Object? userRaw = json['user'];
    if (userRaw is! Map) {
      throw FormatException('verify-otp response missing user object: $json');
    }
    return AuthSession(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      user: RiderUser.fromJson(Map<String, dynamic>.from(userRaw)),
    );
  }

  /// Short-lived JWT (15 minutes on the live backend).
  final String accessToken;

  /// Long-lived JWT (7 days on the live backend). Rotates on every
  /// refresh.
  final String refreshToken;

  /// Authenticated rider user.
  final RiderUser user;

  /// Returns a copy with new [accessToken]/[refreshToken] but the same
  /// [user]. Used after `/auth/refresh-token`.
  AuthSession copyWithTokens({
    required String accessToken,
    required String refreshToken,
  }) {
    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: user,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AuthSession &&
        other.accessToken == accessToken &&
        other.refreshToken == refreshToken &&
        other.user == user;
  }

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, user);
}
