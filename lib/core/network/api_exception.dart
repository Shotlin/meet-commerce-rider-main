import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_envelope.dart';

/// Sealed base class for every network-layer exception in the rider app.
///
/// All transport-level failures (timeouts, offline, 5xx, malformed
/// envelopes) and authenticated-action failures (401, 403, 409, 422) are
/// translated into [ApiException] subtypes by [ApiException.fromDioError]
/// or constructed directly by the auth interceptor / repositories. The
/// presentation layer never sees a raw [DioException]; it only ever
/// pattern-matches on [ApiException] subtypes via the `ErrorTranslator`
/// (added in a later task).
@immutable
sealed class ApiException implements Exception {
  /// Constructs an exception with a user-facing [message] and optional
  /// transport / backend details.
  const ApiException(
    this.message, {
    this.statusCode,
    this.backendCode,
    this.errors,
    this.cause,
    this.stackTrace,
  });

  /// Human-readable copy. For 4xx/5xx responses this is the backend's
  /// `message` field; for transport failures it's a translated string.
  final String message;

  /// HTTP status code when available. Null for transport-level failures
  /// that never received a response.
  final int? statusCode;

  /// Backend `code` field (e.g. `ORDER_NOT_AVAILABLE`, `INVALID_OTP`).
  /// Null when no envelope was decoded.
  final String? backendCode;

  /// Validation-error rows when the backend returned `VALIDATION_ERROR`.
  final List<Map<String, dynamic>>? errors;

  /// Underlying error (typically a [DioException]) for diagnostic logging.
  final Object? cause;

  /// Stack trace captured at the original throw site.
  final StackTrace? stackTrace;

  /// Translates a [DioException] thrown by Dio into the most specific
  /// [ApiException] subtype.
  ///
  /// The mapping rules:
  /// - `connectionTimeout`/`sendTimeout`/`receiveTimeout` -> [ApiTimeoutException]
  /// - `connectionError`/`unknown` without a response  -> [ApiNetworkException]
  /// - HTTP 401/403                                    -> [ApiAuthException]
  /// - HTTP 409                                        -> [ApiConflictException]
  /// - HTTP 422 with `code: VALIDATION_ERROR`          -> [ApiValidationException]
  /// - HTTP 4xx (other)                                -> [ApiValidationException]
  /// - HTTP 5xx                                        -> [ApiServerException]
  /// - anything else                                   -> [ApiUnknownException]
  static ApiException fromDio(DioException error) {
    final Response<dynamic>? response = error.response;
    final int? status = response?.statusCode;
    final ApiEnvelope<Object?>? envelope = _decodeEnvelope(response?.data);
    final String? envelopeMessage = (envelope?.message.isNotEmpty ?? false)
        ? envelope!.message
        : null;
    final String? code = envelope?.code;
    final List<Map<String, dynamic>>? errors = envelope?.errors;
    final StackTrace stackTrace = error.stackTrace;

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiTimeoutException(
          envelopeMessage ?? 'Network is slow. Try again',
          cause: error,
          stackTrace: stackTrace,
        );
      case DioExceptionType.connectionError:
        return ApiNetworkException(
          envelopeMessage ?? 'You are offline. Check your connection',
          cause: error,
          stackTrace: stackTrace,
        );
      case DioExceptionType.cancel:
        return ApiUnknownException(
          'Request cancelled',
          statusCode: status,
          backendCode: code,
          cause: error,
          stackTrace: stackTrace,
        );
      case DioExceptionType.badCertificate:
        return ApiNetworkException(
          envelopeMessage ?? 'Could not verify the server certificate',
          cause: error,
          stackTrace: stackTrace,
        );
      case DioExceptionType.unknown:
        // Treat raw socket / connection errors as network failures even
        // when they reach us as `unknown`.
        if (error.error is Exception &&
            error.error.runtimeType.toString() == 'SocketException') {
          return ApiNetworkException(
            envelopeMessage ?? 'You are offline. Check your connection',
            cause: error,
            stackTrace: stackTrace,
          );
        }
        if (status == null) {
          return ApiUnknownException(
            envelopeMessage ?? 'Unknown error',
            cause: error,
            stackTrace: stackTrace,
          );
        }
        return _fromStatus(
          status,
          envelopeMessage,
          code,
          errors,
          error,
          stackTrace,
        );
      case DioExceptionType.badResponse:
        if (status == null) {
          return ApiUnknownException(
            envelopeMessage ?? 'Unknown error',
            cause: error,
            stackTrace: stackTrace,
          );
        }
        return _fromStatus(
          status,
          envelopeMessage,
          code,
          errors,
          error,
          stackTrace,
        );
    }
  }

  static ApiException _fromStatus(
    int status,
    String? envelopeMessage,
    String? code,
    List<Map<String, dynamic>>? errors,
    DioException error,
    StackTrace stackTrace,
  ) {
    final String message = envelopeMessage ?? _defaultMessageForStatus(status);
    if (status == 401 || status == 403) {
      return ApiAuthException(
        message,
        statusCode: status,
        backendCode: code,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (status == 409) {
      return ApiConflictException(
        message,
        statusCode: status,
        backendCode: code,
        errors: errors,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (status >= 400 && status < 500) {
      return ApiValidationException(
        message,
        statusCode: status,
        backendCode: code,
        errors: errors,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (status >= 500) {
      return ApiServerException(
        message,
        statusCode: status,
        backendCode: code,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return ApiUnknownException(
      message,
      statusCode: status,
      backendCode: code,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static String _defaultMessageForStatus(int status) {
    if (status == 401 || status == 403) {
      return 'Your session has expired. Please log in again';
    }
    if (status == 409) return 'Action could not be completed';
    if (status >= 400 && status < 500) return 'Request failed';
    if (status >= 500) {
      return 'Something went wrong on our side. Try again in a moment';
    }
    return 'Unknown error';
  }

  static ApiEnvelope<Object?>? _decodeEnvelope(Object? raw) {
    if (raw is Map) {
      try {
        return ApiEnvelope<Object?>.fromJson(
          Map<String, dynamic>.from(raw),
          (Object? value) => value,
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  String toString() {
    final List<String> parts = <String>[
      runtimeType.toString(),
      if (statusCode != null) 'status=$statusCode',
      if (backendCode != null) 'code=$backendCode',
      'message=$message',
    ];
    return parts.join(' ');
  }
}

/// Connect / read / send timeout from Dio (transport never completed).
final class ApiTimeoutException extends ApiException {
  const ApiTimeoutException(super.message, {super.cause, super.stackTrace});
}

/// Connectivity loss or DNS / certificate failure. Surface the offline
/// banner; do not retry automatically.
final class ApiNetworkException extends ApiException {
  const ApiNetworkException(super.message, {super.cause, super.stackTrace});
}

/// HTTP 401 / 403. The auth interceptor handles 401 transparently; only
/// surfaces here when the refresh path fails.
final class ApiAuthException extends ApiException {
  const ApiAuthException(
    super.message, {
    super.statusCode,
    super.backendCode,
    super.cause,
    super.stackTrace,
  });
}

/// HTTP 409. The live backend uses a 4xx envelope with code
/// `ORDER_NOT_AVAILABLE` for "order claimed by another rider".
final class ApiConflictException extends ApiException {
  const ApiConflictException(
    super.message, {
    super.statusCode,
    super.backendCode,
    super.errors,
    super.cause,
    super.stackTrace,
  });
}

/// HTTP 4xx / 422 with field-level errors.
final class ApiValidationException extends ApiException {
  const ApiValidationException(
    super.message, {
    super.statusCode,
    super.backendCode,
    super.errors,
    super.cause,
    super.stackTrace,
  });
}

/// HTTP 5xx. Preserve the user's local input on the current screen.
final class ApiServerException extends ApiException {
  const ApiServerException(
    super.message, {
    super.statusCode,
    super.backendCode,
    super.cause,
    super.stackTrace,
  });
}

/// Catch-all for shapes the mapper does not recognize.
final class ApiUnknownException extends ApiException {
  const ApiUnknownException(
    super.message, {
    super.statusCode,
    super.backendCode,
    super.cause,
    super.stackTrace,
  });
}
