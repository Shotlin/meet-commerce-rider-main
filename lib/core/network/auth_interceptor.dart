import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/secure_token_store.dart';
import '../utils/app_logger.dart';

/// Future-returning callback that performs a token refresh and returns
/// `true` when a fresh access/refresh pair was successfully written to
/// the token store, or `false` when the refresh failed and the session
/// must be ended.
typedef TokenRefresher = Future<bool> Function();

/// Mutual-exclusion lock around an in-flight token refresh attempt.
///
/// Property 1 from the design says:
/// - At most one refresh call is in flight at any instant.
/// - Each queued request is retried exactly once with the new access
///   token after a successful refresh.
///
/// `RefreshLock` is the structural form of the first half of that
/// property: every caller that needs a refresh is given the same
/// `Future<bool>`, so [body] is invoked at most once per refresh cycle.
/// On completion the future is cleared so the next 401 cycle can run a
/// fresh refresh.
class RefreshLock {
  Future<bool>? _inFlight;

  /// Returns `true` while a refresh is being awaited by anyone.
  bool get inFlight => _inFlight != null;

  /// Runs [body] under the lock. Concurrent callers receive the same
  /// `Future<bool>` and therefore observe the same outcome. The lock is
  /// released once the future completes (successfully or not).
  Future<bool> run(Future<bool> Function() body) {
    final Future<bool>? current = _inFlight;
    if (current != null) return current;
    // Invoke body synchronously so concurrent callers within the same
    // microtask see `inFlight == true` immediately. A synchronous throw
    // becomes a future error so the lock-release contract holds.
    Future<bool> started;
    try {
      started = body();
    } catch (error, stack) {
      started = Future<bool>.error(error, stack);
    }
    _inFlight = started;
    // Listen with `then` instead of `whenComplete` so the error path is
    // observed (and therefore not flagged as unhandled when the caller
    // attaches its own `expectLater`/await error handler).
    started.then<void>(
      (_) => _release(started),
      onError: (Object _, StackTrace __) => _release(started),
    );
    return started;
  }

  void _release(Future<bool> token) {
    if (identical(_inFlight, token)) _inFlight = null;
  }
}

/// Queued Dio interceptor that attaches the access token, transparently
/// refreshes on 401, and retries the original request exactly once.
///
/// `QueuedInterceptor` serializes `onRequest` and `onError` callbacks
/// across concurrent requests, which combined with [RefreshLock] gives
/// us Property 1 from the design without re-implementing the queue.
///
/// Behaviour:
/// 1. `onRequest` reads the latest access token from [tokenStore] and
///    sets the `Authorization: Bearer ...` header.
/// 2. `onError` for HTTP 401 calls [refresh] under the lock. Concurrent
///    401s on other requests await the same refresh future.
/// 3. On a successful refresh, the original request is cloned with the
///    new access token and replayed exactly once.
/// 4. If the refresh fails, the auth exception is forwarded to the
///    caller so the session controller can route to the login screen.
class AuthInterceptor extends QueuedInterceptor {
  /// Constructs the interceptor.
  AuthInterceptor({
    required SecureTokenStore tokenStore,
    required TokenRefresher refresh,
    required Dio retryDio,
    RefreshLock? lock,
  }) : _tokenStore = tokenStore,
       _refresh = refresh,
       _retryDio = retryDio,
       _lock = lock ?? RefreshLock();

  final SecureTokenStore _tokenStore;
  final TokenRefresher _refresh;
  final Dio _retryDio;
  final RefreshLock _lock;

  /// Set of request paths flagged with `Authorization: skip-auth-refresh`,
  /// or by header value. Used by `/auth/refresh-token` itself so a 401
  /// on the refresh path doesn't recursively trigger another refresh.
  static const String skipHeaderName = 'X-Skip-Auth-Refresh';

  static const String skipHeaderValue = '1';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isRefreshSkipped(options)) {
      handler.next(options);
      return;
    }
    final String? token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final Response<dynamic>? response = err.response;
    final int? status = response?.statusCode;
    final RequestOptions options = err.requestOptions;

    if (status != 401 || _isRefreshSkipped(options)) {
      handler.next(err);
      return;
    }

    AppLogger.info(
      LogTopic.auth,
      'AuthInterceptor: 401 on ${options.method} ${options.path}; '
      'attempting refresh',
    );

    // If the request was issued with a stale access token (the token
    // changed between when this request was sent and when this 401 was
    // dispatched, e.g. because a sibling request already triggered the
    // refresh), skip the refresh entirely and just retry with the
    // current token. This is the second half of Property 1: under
    // QueuedInterceptor's serialized onError dispatch, only the first
    // 401 in a burst should call the refresher.
    final String? requestedToken = _bearerToken(options);
    final String? currentToken = await _tokenStore.readAccessToken();
    final bool tokenAlreadyRotated =
        requestedToken != null &&
        currentToken != null &&
        currentToken.isNotEmpty &&
        currentToken != requestedToken;

    bool refreshed = tokenAlreadyRotated;
    if (!refreshed) {
      refreshed = await _lock.run(_refresh);
    }

    if (!refreshed) {
      AppLogger.warn(
        LogTopic.auth,
        'AuthInterceptor: refresh failed; forwarding 401 to caller',
      );
      handler.next(err);
      return;
    }

    final String? newToken = await _tokenStore.readAccessToken();
    if (newToken == null || newToken.isEmpty) {
      AppLogger.warn(
        LogTopic.auth,
        'AuthInterceptor: refresh returned ok but no token in store',
      );
      handler.next(err);
      return;
    }

    try {
      final Response<dynamic> retried = await _retryDio.fetch<dynamic>(
        _cloneWithToken(options, newToken),
      );
      handler.resolve(retried);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  String? _bearerToken(RequestOptions options) {
    final Object? value = options.headers['Authorization'];
    if (value is String && value.startsWith('Bearer ')) {
      return value.substring('Bearer '.length);
    }
    return null;
  }

  bool _isRefreshSkipped(RequestOptions options) {
    final Object? value = options.headers[skipHeaderName];
    return value == skipHeaderValue || value == true;
  }

  RequestOptions _cloneWithToken(RequestOptions src, String token) {
    final Map<String, dynamic> headers = Map<String, dynamic>.from(src.headers);
    headers['Authorization'] = 'Bearer $token';
    // Mark the retry so a hypothetical *second* 401 on the retry path
    // doesn't kick off yet another refresh cycle (defence in depth).
    headers[skipHeaderName] = skipHeaderValue;
    return src.copyWith(headers: headers);
  }
}
