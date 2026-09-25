import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/secure_token_store.dart';
import '../../../core/utils/app_logger.dart';
import '../data/auth_repository.dart';
import '../domain/auth_session.dart';
import '../domain/rider_user.dart';
import 'auth_controller.dart';
import 'auth_state.dart';
import 'session_state.dart';

/// Coordinates app-startup routing based on the persisted session.
///
/// On app launch, [restore] reads the secure token store and either:
/// - routes to the login screen (no token), or
/// - calls `GET /delivery/profile` to confirm the token is still valid
///   and to read the rider's approval status.
///
/// The interceptor (Task 2.3) handles the 401 case transparently — by
/// the time `restore` sees a result, the token is already fresh.
///
/// `SessionController` is also the seam the rest of the app uses to
/// observe the verified rider after login: when the auth flow finishes,
/// `AuthController` calls into [adoptVerifiedSession] to update the
/// state without re-fetching the profile.
class SessionController extends ChangeNotifier {
  /// Wires the controller to its dependencies.
  SessionController({
    required ApiClient apiClient,
    required AuthRepository authRepository,
    required SecureTokenStore tokenStore,
  }) : _apiClient = apiClient,
       _authRepository = authRepository,
       _tokenStore = tokenStore;

  final ApiClient _apiClient;
  final AuthRepository _authRepository;
  final SecureTokenStore _tokenStore;

  SessionState _state = const SessionState.unknown();

  /// Latest session snapshot. Listeners receive a [notifyListeners]
  /// call when this value changes.
  SessionState get state => _state;

  void _emit(SessionState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  /// Loads tokens from the secure store, then either routes to login
  /// or fetches the rider profile to determine approval status.
  ///
  /// Always emits a non-[SessionPhase.unknown] state when it returns,
  /// so the router can navigate decisively.
  Future<void> restore() async {
    final String? accessToken = await _tokenStore.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      _emit(const SessionState(phase: SessionPhase.unauthenticated));
      return;
    }
    try {
      final ApiEnvelope<Map<String, dynamic>> envelope = await _apiClient
          .get<Map<String, dynamic>>(
            '/delivery/profile',
            parseData: (Object? raw) {
              if (raw is Map) {
                return Map<String, dynamic>.from(raw);
              }
              throw DioException(
                requestOptions: RequestOptions(path: '/delivery/profile'),
                type: DioExceptionType.badResponse,
                message: 'profile returned malformed payload: $raw',
              );
            },
          );
      final Map<String, dynamic>? profile = envelope.data;
      if (profile == null) {
        _emit(
          const SessionState(
            phase: SessionPhase.unauthenticated,
            errorMessage: 'Could not load your profile. Please sign in again',
          ),
        );
        await _tokenStore.clear();
        return;
      }
      final bool approved = _readBool(profile['is_approved']) ?? false;
      final RiderUser user = _userFromProfile(profile);
      _emit(
        SessionState(
          phase: approved ? SessionPhase.approved : SessionPhase.unverified,
          user: user,
        ),
      );
    } on ApiAuthException catch (error, stack) {
      // A 401 here can mean two different things: the refresh token is
      // genuinely dead, or the silent refresh attempt behind this
      // request merely failed transiently (network blip / timeout /
      // 5xx) and this 401 is just the original expired access token
      // falling through. AuthRepository.refreshTokens() only clears the
      // token store on a *confirmed* rejection from the backend, so if
      // a refresh token is still there, this was the transient case —
      // wiping a perfectly valid 365-day session over a momentary
      // network hiccup is exactly the false-logout bug this guards
      // against.
      final String? remainingRefreshToken = await _tokenStore
          .readRefreshToken();
      if (remainingRefreshToken == null || remainingRefreshToken.isEmpty) {
        AppLogger.warn(
          LogTopic.auth,
          'SessionController.restore: auth failed; clearing session',
          error: error,
          stackTrace: stack,
        );
        await _authRepository.logout();
        _emit(const SessionState(phase: SessionPhase.unauthenticated));
        return;
      }

      AppLogger.warn(
        LogTopic.auth,
        'SessionController.restore: transient failure during session '
        'verification; keeping session for retry',
        error: error,
        stackTrace: stack,
      );
      _emit(
        const SessionState(
          phase: SessionPhase.unauthenticated,
          errorMessage: 'Could not verify your session. Please try again.',
        ),
      );
    } on ApiException catch (error, stack) {
      // Network or server failure; stay unauthenticated but keep the
      // token so the rider can retry from the splash screen.
      AppLogger.warn(
        LogTopic.auth,
        'SessionController.restore: profile fetch failed',
        error: error,
        stackTrace: stack,
      );
      _emit(
        SessionState(
          phase: SessionPhase.unauthenticated,
          errorMessage: error.message,
        ),
      );
    }
  }

  /// Reflects a successful login into the session state without making
  /// a profile call. Called by `AuthController` once verify-otp returns.
  void adoptVerifiedSession(RiderUser user, {required bool isApproved}) {
    _emit(
      SessionState(
        phase: isApproved ? SessionPhase.approved : SessionPhase.unverified,
        user: user,
      ),
    );
    // Register FCM token with backend after login (fire-and-forget).
    _registerFcmToken();
  }

  /// Registers the FCM token with the Bakaloo backend after login.
  void _registerFcmToken() {
    final String? token = NotificationService.instance.fcmToken;
    if (token == null || token.isEmpty) return;
    _apiClient
        .post<Object?>(
          '/notifications/tokens',
          body: <String, dynamic>{'token': token, 'platform': 'android'},
          parseData: (Object? raw) => raw,
        )
        .then(
          (_) => AppLogger.info(
            LogTopic.notifications,
            'FCM token registered with backend',
          ),
        )
        .catchError(
          (Object e) => AppLogger.warn(
            LogTopic.notifications,
            'FCM token registration failed: $e',
          ),
        );
  }

  /// Convenience used by the router to react to login flow completion.
  void linkAuthController(AuthController auth) {
    auth.addListener(() {
      final AuthSession? session = auth.state.session;
      if (session != null && auth.state.phase == AuthPhase.verified) {
        // The /delivery/profile call right after login may report a
        // different `is_approved` than `user.isVerified`. Optimistically
        // mark unverified; the next /delivery/profile fetch (e.g. when
        // the home shell mounts) will upgrade to approved.
        adoptVerifiedSession(session.user, isApproved: session.user.isVerified);
      }
    });
  }

  /// Logs out and resets the session state to unauthenticated.
  Future<void> logout() async {
    await _authRepository.logout();
    _emit(const SessionState(phase: SessionPhase.unauthenticated));
  }

  static RiderUser _userFromProfile(Map<String, dynamic> profile) {
    return RiderUser(
      id: (profile['user_id'] as String?) ?? (profile['id'] as String?) ?? '',
      phone: (profile['phone'] as String?) ?? '',
      name: profile['name'] as String?,
      role: 'RIDER',
      isNewUser: false,
      isVerified: _readBool(profile['is_approved']) ?? false,
    );
  }

  static bool? _readBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'true':
        case '1':
          return true;
        case 'false':
        case '0':
          return false;
      }
    }
    return null;
  }
}
