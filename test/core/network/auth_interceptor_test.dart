import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/network/auth_interceptor.dart';
import 'package:meet_commerce_rider_main/core/storage/secure_token_store.dart';

/// Tests for [AuthInterceptor], focused on Property 1 from the design:
/// - At most one refresh is in flight at any instant.
/// - Each queued request is retried exactly once with the new access token.
///
/// We hand-roll a tiny `HttpClientAdapter` instead of pulling in
/// `http_mock_adapter` so the test has no extra dependency. The adapter
/// can return 401 once per path and 200 thereafter, while counting the
/// number of times each path was called.
class _StubAdapter implements HttpClientAdapter {
  /// Maps a path to the responses to serve, in order. When the list
  /// runs out the adapter returns the last response repeatedly.
  final Map<String, List<int>> statusByPath = <String, List<int>>{};

  /// Number of times each path has been called.
  final Map<String, int> callsByPath = <String, int>{};

  /// Tokens observed per call, in order, for assertions about the retry
  /// carrying the new access token.
  final List<String?> tokensSeenInOrder = <String?>[];

  /// Tokens observed per path.
  final Map<String, List<String?>> tokensByPath = <String, List<String?>>{};

  /// Optional delay to inject before responding so we can interleave
  /// concurrent calls deterministically.
  Duration? perCallDelay;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String path = options.path;
    callsByPath[path] = (callsByPath[path] ?? 0) + 1;
    final String? auth = options.headers['Authorization'] as String?;
    tokensSeenInOrder.add(auth);
    tokensByPath.putIfAbsent(path, () => <String?>[]).add(auth);

    if (perCallDelay != null) {
      await Future<void>.delayed(perCallDelay!);
    }

    final List<int> statuses = statusByPath[path] ?? <int>[200];
    final int statusToServe = statuses.isNotEmpty
        ? (statuses.length == 1 ? statuses.first : statuses.removeAt(0))
        : 200;

    final Map<String, dynamic> body = statusToServe == 401
        ? <String, dynamic>{
            'success': false,
            'message': 'Unauthorized',
            'code': 'UNAUTHORIZED',
          }
        : <String, dynamic>{
            'success': true,
            'message': 'OK',
            'data': <String, dynamic>{},
          };

    return ResponseBody.fromString(
      jsonEncode(body),
      statusToServe,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

Dio _buildDio(_StubAdapter adapter) {
  return Dio(
    BaseOptions(
      baseUrl: 'https://example.test',
      contentType: 'application/json',
      validateStatus: (int? status) =>
          status != null && status >= 200 && status < 300,
    ),
  )..httpClientAdapter = adapter;
}

void main() {
  group('AuthInterceptor.onRequest', () {
    test('attaches the bearer token from the store', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusByPath['/protected'] = <int>[200];
      final Dio retryDio = _buildDio(adapter);
      final Dio dio = _buildDio(adapter);
      final SecureTokenStore store = InMemoryTokenStore(
        accessToken: 'A',
        refreshToken: 'R',
      );

      dio.interceptors.add(
        AuthInterceptor(
          tokenStore: store,
          refresh: () async => true,
          retryDio: retryDio,
        ),
      );

      await dio.get<dynamic>('/protected');

      expect(adapter.callsByPath['/protected'], 1);
      expect(adapter.tokensByPath['/protected']!.first, 'Bearer A');
    });
  });

  group('AuthInterceptor 401 -> refresh -> retry', () {
    test(
      'refreshes once and retries the original request exactly once',
      () async {
        final _StubAdapter adapter = _StubAdapter()
          ..statusByPath['/protected'] = <int>[401, 200];
        final Dio retryDio = _buildDio(adapter);
        final Dio dio = _buildDio(adapter);
        final SecureTokenStore store = InMemoryTokenStore(
          accessToken: 'A',
          refreshToken: 'R',
        );

        int refreshCount = 0;

        dio.interceptors.add(
          AuthInterceptor(
            tokenStore: store,
            refresh: () async {
              refreshCount++;
              await store.writeTokens(accessToken: 'A2', refreshToken: 'R2');
              return true;
            },
            retryDio: retryDio,
          ),
        );

        final Response<dynamic> response = await dio.get<dynamic>('/protected');
        expect(response.statusCode, 200);

        // Two calls: original 401 + retry.
        expect(adapter.callsByPath['/protected'], 2);
        // Token sequence: original "Bearer A", retry "Bearer A2".
        expect(adapter.tokensByPath['/protected'], <String>[
          'Bearer A',
          'Bearer A2',
        ]);
        // Refresh ran exactly once.
        expect(refreshCount, 1);
      },
    );

    test('forwards 401 when refresh returns false', () async {
      final _StubAdapter adapter = _StubAdapter()
        ..statusByPath['/protected'] = <int>[401];
      final Dio retryDio = _buildDio(adapter);
      final Dio dio = _buildDio(adapter);
      final SecureTokenStore store = InMemoryTokenStore(
        accessToken: 'A',
        refreshToken: 'R',
      );

      dio.interceptors.add(
        AuthInterceptor(
          tokenStore: store,
          refresh: () async => false,
          retryDio: retryDio,
        ),
      );

      await expectLater(
        dio.get<dynamic>('/protected'),
        throwsA(isA<DioException>()),
      );

      expect(adapter.callsByPath['/protected'], 1); // no retry
    });

    test(
      'N concurrent 401s share one refresh and each retries exactly once',
      () async {
        // 5 distinct paths, all 401 once, then 200.
        final _StubAdapter adapter = _StubAdapter()
          ..perCallDelay = const Duration(milliseconds: 5);
        for (int i = 0; i < 5; i++) {
          adapter.statusByPath['/p$i'] = <int>[401, 200];
        }
        final Dio retryDio = _buildDio(adapter);
        final Dio dio = _buildDio(adapter);
        final SecureTokenStore store = InMemoryTokenStore(
          accessToken: 'A',
          refreshToken: 'R',
        );

        int refreshCount = 0;

        dio.interceptors.add(
          AuthInterceptor(
            tokenStore: store,
            refresh: () async {
              refreshCount++;
              // Simulate the refresh taking a small amount of time.
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await store.writeTokens(accessToken: 'A2', refreshToken: 'R2');
              return true;
            },
            retryDio: retryDio,
          ),
        );

        final List<Future<Response<dynamic>>> calls =
            <Future<Response<dynamic>>>[
              for (int i = 0; i < 5; i++) dio.get<dynamic>('/p$i'),
            ];

        final List<Response<dynamic>> responses = await Future.wait(calls);

        // All five succeeded.
        expect(
          responses.every((Response<dynamic> r) => r.statusCode == 200),
          isTrue,
        );
        // Refresh ran exactly once across the burst — Property 1 (mutex).
        expect(refreshCount, 1);
        // Each path saw exactly the original + one retry — Property 1 (exactly-once).
        for (int i = 0; i < 5; i++) {
          expect(adapter.callsByPath['/p$i'], 2);
          expect(
            adapter.tokensByPath['/p$i'],
            <String>['Bearer A', 'Bearer A2'],
            reason: 'path /p$i must retry exactly once with the new token',
          );
        }
      },
    );
  });
}
