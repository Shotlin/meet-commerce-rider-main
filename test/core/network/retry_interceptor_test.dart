import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/network/retry_interceptor.dart';

/// Minimal [HttpClientAdapter] stub.
///
/// Each path in [statusSequences] is served in order on successive
/// calls. When a path's sequence is exhausted, the last status is
/// repeated. Defaults to 200 for unknown paths.
///
/// For timeout simulation, return [_kTimeoutStatus] which is intercepted
/// below the HTTP layer to emit a DioExceptionType.receiveTimeout.
class _StubAdapter implements HttpClientAdapter {
  /// Sentinel that causes the stub to throw a receiveTimeout error.
  static const int kTimeoutStatus = -1;

  /// Sentinel for a connection error (no response).
  static const int kNetworkErrorStatus = -2;

  final Map<String, List<int>> statusSequences = <String, List<int>>{};
  final Map<String, int> callCounts = <String, int>{};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String path = options.path;
    callCounts[path] = (callCounts[path] ?? 0) + 1;

    final List<int> statuses = statusSequences[path] ?? <int>[200];
    final int status = statuses.length == 1
        ? statuses.first
        : statuses.removeAt(0);

    if (status == kTimeoutStatus) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
        message: 'Receive timeout',
      );
    }
    if (status == kNetworkErrorStatus) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Connection error',
      );
    }

    final Map<String, dynamic> body = status >= 200 && status < 300
        ? <String, dynamic>{
            'success': true,
            'message': 'OK',
            'data': <String, dynamic>{},
          }
        : <String, dynamic>{'success': false, 'message': 'Error'};

    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

Dio _buildDio(
  _StubAdapter adapter, {
  Duration firstDelay = Duration.zero,
  Duration secondDelay = Duration.zero,
  int maxRetries = 2,
}) {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: 'https://example.test',
      validateStatus: (int? s) => s != null && s >= 200 && s < 600,
    ),
  )..httpClientAdapter = adapter;

  // Inject the Dio reference into extras (mimics what ApiClient._buildDio does).
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        options.extra[RetryInterceptor.extraDioKey] = dio;
        handler.next(options);
      },
    ),
  );

  dio.interceptors.add(
    RetryInterceptor(
      maxRetries: maxRetries,
      firstDelay: firstDelay,
      secondDelay: secondDelay,
    ),
  );

  return dio;
}

void main() {
  group('RetryInterceptor – GET retries on timeout', () {
    test('GET retries once after receiveTimeout, succeeds on retry', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusSequences['/data'] = <int>[_StubAdapter.kTimeoutStatus, 200];
      final Dio dio = _buildDio(adapter);

      final Response<dynamic> response = await dio.get<dynamic>('/data');

      expect(response.statusCode, 200);
      expect(adapter.callCounts['/data'], 2); // initial + 1 retry
    });

    test('GET retries twice after two timeouts, succeeds on third', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusSequences['/data'] = <int>[
          _StubAdapter.kTimeoutStatus,
          _StubAdapter.kTimeoutStatus,
          200,
        ];
      final Dio dio = _buildDio(adapter);

      final Response<dynamic> response = await dio.get<dynamic>('/data');

      expect(response.statusCode, 200);
      expect(adapter.callCounts['/data'], 3); // initial + 2 retries
    });

    test('GET retries on ApiNetworkException (connectionError)', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusSequences['/data'] = <int>[
          _StubAdapter.kNetworkErrorStatus,
          200,
        ];
      final Dio dio = _buildDio(adapter);

      final Response<dynamic> response = await dio.get<dynamic>('/data');

      expect(response.statusCode, 200);
      expect(adapter.callCounts['/data'], 2);
    });
  });

  group('RetryInterceptor – no retry for non-GET methods', () {
    test('PATCH does not retry on timeout', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusSequences['/action'] = <int>[_StubAdapter.kTimeoutStatus, 200];
      final Dio dio = _buildDio(adapter);

      await expectLater(
        dio.patch<dynamic>('/action'),
        throwsA(isA<DioException>()),
      );

      // Only the initial call was made; no retry.
      expect(adapter.callCounts['/action'], 1);
    });

    test('POST does not retry on timeout', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusSequences['/submit'] = <int>[_StubAdapter.kTimeoutStatus, 200];
      final Dio dio = _buildDio(adapter);

      await expectLater(
        dio.post<dynamic>('/submit'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCounts['/submit'], 1);
    });

    test('DELETE does not retry on timeout', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusSequences['/item'] = <int>[_StubAdapter.kTimeoutStatus, 200];
      final Dio dio = _buildDio(adapter);

      await expectLater(
        dio.delete<dynamic>('/item'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCounts['/item'], 1);
    });
  });

  group('RetryInterceptor – max 2 retries then rethrows', () {
    test('three consecutive timeouts exhaust retries and rethrows', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusSequences['/flaky'] = <int>[
          _StubAdapter.kTimeoutStatus,
          _StubAdapter.kTimeoutStatus,
          _StubAdapter.kTimeoutStatus,
          200, // never reached
        ];
      final Dio dio = _buildDio(adapter);

      await expectLater(
        dio.get<dynamic>('/flaky'),
        throwsA(isA<DioException>()),
      );
      // initial + 2 retries = 3 calls total; the 4th (200) is never hit.
      expect(adapter.callCounts['/flaky'], 3);
    });

    test('non-transient 4xx error is not retried', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusSequences['/bad'] = <int>[404, 200];
      final Dio dio = _buildDio(adapter);

      // 404 does not trigger retry (not a timeout/network error).
      final Response<dynamic> response = await dio.get<dynamic>('/bad');
      expect(response.statusCode, 404);
      expect(adapter.callCounts['/bad'], 1);
    });
  });
}
