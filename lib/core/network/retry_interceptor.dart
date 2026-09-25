import 'dart:async';

import 'package:dio/dio.dart';

/// Dio interceptor that retries idempotent GET requests on timeout or
/// network errors (R27 retry semantics).
///
/// Rules:
/// - Only retries GET requests (state-changing POST/PATCH/DELETE are
///   never retried automatically).
/// - Max [maxRetries] retries with delays [firstDelay] then [secondDelay].
/// - Rethrows after the final attempt.
class RetryInterceptor extends Interceptor {
  /// Constructs a retry interceptor with configurable delays.
  RetryInterceptor({
    this.maxRetries = 2,
    this.firstDelay = const Duration(milliseconds: 200),
    this.secondDelay = const Duration(milliseconds: 600),
  });

  /// Max number of retries.
  final int maxRetries;

  /// Delay before the first retry.
  final Duration firstDelay;

  /// Delay before the second retry.
  final Duration secondDelay;

  /// Key used in `RequestOptions.extra` to stash the Dio instance for
  /// retries. The `ApiClient` sets this so the retry goes through the
  /// same Dio (with interceptors) rather than a bare one.
  static const String extraDioKey = '_retryDio';

  /// Key used in `RequestOptions.extra` to track the current attempt.
  static const String _attemptKey = '_retryAttempt';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;

    // Only retry GET requests.
    if (options.method.toUpperCase() != 'GET') {
      handler.next(err);
      return;
    }

    // Only retry on timeout or connection errors.
    final bool isRetryable =
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;

    if (!isRetryable) {
      handler.next(err);
      return;
    }

    // Read the current attempt count from extras.
    final int attempt = (options.extra[_attemptKey] as int?) ?? 0;
    if (attempt >= maxRetries) {
      handler.next(err);
      return;
    }

    // Wait then retry.
    final Duration delay = attempt == 0 ? firstDelay : secondDelay;
    await Future<void>.delayed(delay);
    options.extra[_attemptKey] = attempt + 1;

    // Use the stashed Dio if available (preserves interceptors), else
    // fall back to a bare fetch.
    final Object? stashedDio = options.extra[extraDioKey];
    final Dio dio = stashedDio is Dio ? stashedDio : Dio();

    try {
      final Response<dynamic> response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      // Recurse: the next attempt will increment the counter.
      await onError(retryErr, handler);
    }
  }
}
