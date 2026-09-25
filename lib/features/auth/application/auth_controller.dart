import 'package:flutter/foundation.dart';

import '../../../core/config/app_constants.dart';
import '../../../core/utils/app_logger.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../domain/auth_exception.dart';
import '../domain/auth_session.dart';
import 'auth_state.dart';

/// Controls the phone OTP login flow on top of [AuthRepository].
///
/// `AuthController` owns the [AuthState] machine consumed by the
/// `PhoneLoginScreen` and `OtpScreen`. It is deliberately a plain
/// `ChangeNotifier` (rather than a Riverpod `Notifier`) so it can be
/// wired in equally well from a `ProviderScope` or a vanilla
/// `ChangeNotifierProvider` without forcing the codegen toolchain.
class AuthController extends ChangeNotifier {
  /// Constructs a controller backed by [_repository], with [_now] used
  /// to compute the resend-OTP cooldown so tests can supply a fake clock.
  AuthController({
    required AuthRepository repository,
    DateTime Function() now = _systemNow,
  }) : _repository = repository,
       _now = now;

  final AuthRepository _repository;
  final DateTime Function() _now;

  AuthState _state = const AuthState.initial();

  /// Latest published state. Listeners receive a [notifyListeners] call
  /// whenever this value is replaced.
  AuthState get state => _state;

  /// Replaces [_state] and notifies listeners.
  void _emit(AuthState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  /// Replaces the current state with [AuthState.initial], typically
  /// when the rider returns to the login screen after a failed login.
  void reset() {
    _emit(const AuthState.initial());
  }

  /// Sends an OTP to [rawPhone] and transitions to [AuthPhase.awaitingOtp]
  /// on success.
  ///
  /// Returns `true` when the OTP was sent successfully so callers can
  /// route to the OTP screen.
  Future<bool> sendOtp(String rawPhone) async {
    _emit(
      state.copyWith(
        phase: AuthPhase.sendingOtp,
        clearError: true,
        clearDevOtp: true,
      ),
    );
    try {
      final SendOtpResult result = await _repository.sendOtp(rawPhone);
      final String canonical = AuthRepository.canonicalizePhone(rawPhone);
      final DateTime unlockAt = _now().add(AppConstants.otpResendCooldown);
      _emit(
        state.copyWith(
          phase: AuthPhase.awaitingOtp,
          phone: canonical,
          devOtp: result.devOtp,
          resendUnlockAt: unlockAt,
          clearError: true,
        ),
      );
      return true;
    } on AuthException catch (error, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'AuthController.sendOtp failed: ${error.message}',
        error: error,
        stackTrace: stack,
      );
      _emit(
        state.copyWith(
          phase: AuthPhase.idle,
          errorMessage: error.message,
          clearDevOtp: true,
          clearResendUnlock: true,
        ),
      );
      return false;
    }
  }

  /// Resends the OTP for the current [AuthState.phone] when the cooldown
  /// has elapsed. Returns `false` if no phone is set or the cooldown is
  /// still in effect.
  Future<bool> resendOtp() async {
    final String? phone = state.phone;
    if (phone == null) return false;
    if (!canResend()) return false;
    return sendOtp(phone);
  }

  /// True when the resend-OTP control should be tappable.
  bool canResend() {
    final DateTime? unlockAt = state.resendUnlockAt;
    if (unlockAt == null) return true;
    return !_now().isBefore(unlockAt);
  }

  /// Seconds remaining on the resend cooldown. Zero when the cooldown
  /// has elapsed; useful for binding to a countdown label.
  int resendSecondsRemaining() {
    final DateTime? unlockAt = state.resendUnlockAt;
    if (unlockAt == null) return 0;
    final int remaining = unlockAt.difference(_now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Verifies the entered [otp] and transitions to [AuthPhase.verified]
  /// on success. Returns the verified [AuthSession] or `null` on failure.
  Future<AuthSession?> verifyOtp(String otp) async {
    final String? phone = state.phone;
    if (phone == null) {
      _emit(
        state.copyWith(
          phase: AuthPhase.idle,
          errorMessage: 'Enter your phone number to receive an OTP',
        ),
      );
      return null;
    }
    _emit(state.copyWith(phase: AuthPhase.verifyingOtp, clearError: true));
    try {
      final AuthSession session = await _repository.verifyOtp(
        rawPhone: phone,
        otp: otp.trim(),
      );
      _emit(
        state.copyWith(
          phase: AuthPhase.verified,
          session: session,
          clearError: true,
          clearDevOtp: true,
          clearResendUnlock: true,
        ),
      );
      return session;
    } on AuthException catch (error, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'AuthController.verifyOtp failed: ${error.message}',
        error: error,
        stackTrace: stack,
      );
      _emit(
        state.copyWith(
          phase: AuthPhase.awaitingOtp,
          errorMessage: error.message,
        ),
      );
      return null;
    }
  }

  /// Hits the logout endpoint and clears the local session.
  Future<void> logout() async {
    await _repository.logout();
    _emit(const AuthState.initial());
  }

  static DateTime _systemNow() => DateTime.now();
}
