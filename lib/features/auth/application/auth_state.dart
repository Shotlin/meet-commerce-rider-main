import 'package:flutter/foundation.dart';

import '../domain/auth_session.dart';
import '../domain/rider_user.dart';

/// Phase of the OTP login flow tracked by [AuthController].
///
/// The state machine is:
///
/// ```
/// idle -> sendingOtp -> awaitingOtp -> verifyingOtp -> verified
///                              ^
///                              \--<-- failure -<-- idle/awaitingOtp
/// ```
enum AuthPhase {
  /// Nothing in flight. The login screen is interactive.
  idle,

  /// `/auth/send-otp` is in flight; UI shows a spinner on the Send OTP
  /// button.
  sendingOtp,

  /// OTP successfully sent; the OTP screen is waiting for the rider to
  /// enter the 6-digit code.
  awaitingOtp,

  /// `/auth/verify-otp` is in flight; UI shows a spinner on the Verify
  /// button.
  verifyingOtp,

  /// Verification succeeded; the controller has persisted tokens and
  /// the router can move to home/approval.
  verified,
}

/// Snapshot consumed by login + OTP screens.
@immutable
class AuthState {
  /// Constructs a snapshot explicitly.
  const AuthState({
    required this.phase,
    this.phone,
    this.devOtp,
    this.errorMessage,
    this.session,
    this.resendUnlockAt,
  });

  /// Initial state for a fresh app launch / fresh login screen.
  const AuthState.initial() : this(phase: AuthPhase.idle);

  /// Current phase of the flow.
  final AuthPhase phase;

  /// Phone number the rider is logging in with (E.164 form).
  final String? phone;

  /// Dev-only OTP echoed by the live backend's send-otp response. The
  /// presentation layer surfaces this only under the `dev` flavor.
  final String? devOtp;

  /// User-facing error copy from the latest failed call. Cleared on the
  /// next successful action.
  final String? errorMessage;

  /// Set after `/auth/verify-otp` succeeds and tokens are persisted.
  final AuthSession? session;

  /// Wall-clock instant when the resend-OTP button becomes interactive
  /// again. Computed on transition into [AuthPhase.awaitingOtp].
  final DateTime? resendUnlockAt;

  /// Convenience: the verified rider user when [phase] is
  /// [AuthPhase.verified].
  RiderUser? get user => session?.user;

  /// Returns `true` while the controller is awaiting a backend response.
  bool get isBusy =>
      phase == AuthPhase.sendingOtp || phase == AuthPhase.verifyingOtp;

  /// Builds a copy with selected fields replaced. Pass `null` to clear
  /// optional fields explicitly via the `clear*` flags.
  AuthState copyWith({
    AuthPhase? phase,
    String? phone,
    String? devOtp,
    String? errorMessage,
    AuthSession? session,
    DateTime? resendUnlockAt,
    bool clearError = false,
    bool clearDevOtp = false,
    bool clearSession = false,
    bool clearResendUnlock = false,
  }) {
    return AuthState(
      phase: phase ?? this.phase,
      phone: phone ?? this.phone,
      devOtp: clearDevOtp ? null : (devOtp ?? this.devOtp),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      session: clearSession ? null : (session ?? this.session),
      resendUnlockAt: clearResendUnlock
          ? null
          : (resendUnlockAt ?? this.resendUnlockAt),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AuthState &&
        other.phase == phase &&
        other.phone == phone &&
        other.devOtp == devOtp &&
        other.errorMessage == errorMessage &&
        other.session == session &&
        other.resendUnlockAt == resendUnlockAt;
  }

  @override
  int get hashCode =>
      Object.hash(phase, phone, devOtp, errorMessage, session, resendUnlockAt);
}
