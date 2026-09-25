import 'package:dio/dio.dart';

import '../config/app_constants.dart';
import '../config/env.dart';
import '../utils/app_logger.dart';
import 'api_envelope.dart';
import 'api_exception.dart';
import 'retry_interceptor.dart';

/// Singleton wrapper around a configured [Dio] instance.
///
/// `ApiClient` is the only place that knows the live Meet Commerce REST base
/// URL. Every feature-level API client (`AuthApi`, `DeliveryApi`, etc.)
/// receives an [ApiClient] via its constructor and calls into [request]
/// instead of using Dio directly.
///
/// The auth interceptor is attached separately by Task 2.3; until then,
/// [ApiClient.unauthenticated] builds a client with no interceptors so
/// that auth-bootstrap calls (send-OTP, verify-OTP) can already work.
class ApiClient {
  /// Wraps the supplied [dio] singleton.
  ApiClient(this.dio);

  /// Builds a fresh client pointed at the supplied [env].
  ///
  /// No interceptors are installed by this factory; callers (typically
  /// the bootstrap or a Riverpod provider) attach the auth interceptor
  /// after constructing the client because the interceptor needs the
  /// token store and refresh callback to be available first.
  factory ApiClient.unauthenticated(Env env) {
    return ApiClient(_buildDio(env));
  }

  /// The shared Dio singleton.
  final Dio dio;

  /// Convenience: the live REST base URL the client is currently using.
  String get baseUrl => dio.options.baseUrl;

  /// Issues an HTTP request and decodes the response into an
  /// [ApiEnvelope] of [T].
  ///
  /// On any Dio failure the underlying error is translated into the most
  /// specific [ApiException] subtype via [ApiException.fromDioError] and
  /// rethrown. Repositories therefore see a typed exception hierarchy
  /// regardless of whether the failure was a 401, a timeout, or a 5xx.
  ///
  /// `T` is the shape of the inner `data` field. Pass [parseData] that
  /// knows how to map the decoded JSON object/array to your domain type.
  /// For routes whose `data` is `null` on success (e.g. `/delivery/location`),
  /// pass `(_) => null` and treat `envelope.data == null` as success when
  /// `envelope.success == true`.
  Future<ApiEnvelope<T>> request<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    Options? options,
    required T Function(Object?) parseData,
  }) async {
    try {
      final Response<dynamic> response = await dio.request<dynamic>(
        path,
        data: body,
        queryParameters: queryParameters,
        options: (options ?? Options()).copyWith(method: method),
      );
      final Object? data = response.data;
      if (data is! Map) {
        throw ApiUnknownException(
          'Malformed response from server',
          statusCode: response.statusCode,
        );
      }
      final ApiEnvelope<T> envelope = ApiEnvelope<T>.fromJson(
        Map<String, dynamic>.from(data),
        parseData,
      );
      final int? status = response.statusCode;
      if (envelope.success && status != null && status >= 200 && status < 300) {
        return envelope;
      }
      // Backend reported failure or returned a non-2xx status. Translate
      // it into the appropriate typed exception while preserving the
      // backend message and code so the UI can render the right copy.
      throw _translateFailedEnvelope(
        method: method,
        path: path,
        statusCode: status,
        envelope: envelope,
      );
    } on DioException catch (error) {
      final ApiException translated = ApiException.fromDio(error);
      AppLogger.warn(
        LogTopic.auth, // generic; specific topic chosen by caller as needed
        'HTTP $method $path failed: ${translated.message}',
        error: translated.cause ?? translated,
        stackTrace: translated.stackTrace ?? error.stackTrace,
      );
      throw translated;
    }
  }

  /// Maps an envelope-level failure (HTTP 4xx/5xx or `success: false`)
  /// onto the typed [ApiException] hierarchy. Mirrors the rules in
  /// [ApiException.fromDioError] but operates on a parsed envelope so we
  /// don't re-decode the body.
  static ApiException _translateFailedEnvelope({
    required String method,
    required String path,
    required int? statusCode,
    required ApiEnvelope<Object?> envelope,
  }) {
    final String message = envelope.message.isEmpty
        ? 'Request failed'
        : envelope.message;
    final String? code = envelope.code;
    final List<Map<String, dynamic>>? errors = envelope.errors;
    final int status = statusCode ?? 0;

    if (status == 401 || status == 403) {
      return ApiAuthException(message, statusCode: status, backendCode: code);
    }
    if (status == 409) {
      return ApiConflictException(
        message,
        statusCode: status,
        backendCode: code,
        errors: errors,
      );
    }
    if (status == 422 || (status >= 400 && status < 500)) {
      return ApiValidationException(
        message,
        statusCode: status,
        backendCode: code,
        errors: errors,
      );
    }
    if (status >= 500) {
      return ApiServerException(message, statusCode: status, backendCode: code);
    }
    // 2xx with success: false (the backend doesn't seem to do this in
    // practice, but it's the safe default).
    return ApiUnknownException(
      message,
      statusCode: status == 0 ? null : status,
      backendCode: code,
    );
  }

  /// Convenience wrapper over [request] for `GET`.
  Future<ApiEnvelope<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    required T Function(Object?) parseData,
  }) {
    return request<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      parseData: parseData,
    );
  }

  /// Convenience wrapper over [request] for `POST`.
  Future<ApiEnvelope<T>> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    Options? options,
    required T Function(Object?) parseData,
  }) {
    return request<T>(
      'POST',
      path,
      body: body,
      queryParameters: queryParameters,
      options: options,
      parseData: parseData,
    );
  }

  /// Convenience wrapper over [request] for `PATCH`.
  ///
  /// The live backend rejects `PATCH` calls without a JSON body even
  /// when no parameters are required (returns
  /// `VALIDATION_ERROR: must be object`). Repositories therefore default
  /// the [body] to `const <String, dynamic>{}` instead of leaving it
  /// null, mirroring the live contract.
  Future<ApiEnvelope<T>> patch<T>(
    String path, {
    Object? body = const <String, dynamic>{},
    Map<String, dynamic>? queryParameters,
    Options? options,
    required T Function(Object?) parseData,
  }) {
    return request<T>(
      'PATCH',
      path,
      body: body,
      queryParameters: queryParameters,
      options: options,
      parseData: parseData,
    );
  }

  static Dio _buildDio(Env env) {
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: env.apiBaseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        sendTimeout: AppConstants.sendTimeout,
        contentType: 'application/json',
        responseType: ResponseType.json,
        // Don't throw on 4xx/5xx; the interceptor decides what to do
        // based on status. Without this, Dio would short-circuit before
        // we get a chance to read the envelope's `code`/`message`.
        validateStatus: (int? status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    // Store a reference to the Dio instance in a transformer interceptor
    // so the RetryInterceptor can re-issue requests through the same
    // instance (including its interceptor stack) instead of a bare Dio.
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          // Inject the Dio reference for the RetryInterceptor to pick up.
          options.extra[RetryInterceptor.extraDioKey] = dio;
          handler.next(options);
        },
      ),
    );
    dio.interceptors.add(RetryInterceptor());
    return dio;
  }
}
