import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/network/api_exception.dart';

/// Unit tests for [ApiException.fromDio].
///
/// We synthesize [DioException] instances directly with a fake
/// [RequestOptions] and assert that each Dio failure is bucketed into the
/// expected [ApiException] subtype, with sensible defaults for the
/// user-facing message and the surfaced backend code.
RequestOptions _opts() => RequestOptions(path: '/test');

DioException _bad(int status, {Map<String, dynamic>? body}) {
  final RequestOptions ro = _opts();
  return DioException(
    requestOptions: ro,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: ro,
      statusCode: status,
      data: body,
    ),
  );
}

void main() {
  group('ApiException.fromDio', () {
    test('connectTimeout maps to ApiTimeoutException', () {
      final ApiException ex = ApiException.fromDio(
        DioException(
          requestOptions: _opts(),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      expect(ex, isA<ApiTimeoutException>());
      expect(ex.message, isNotEmpty);
    });

    test('sendTimeout maps to ApiTimeoutException', () {
      final ApiException ex = ApiException.fromDio(
        DioException(
          requestOptions: _opts(),
          type: DioExceptionType.sendTimeout,
        ),
      );
      expect(ex, isA<ApiTimeoutException>());
    });

    test('receiveTimeout maps to ApiTimeoutException', () {
      final ApiException ex = ApiException.fromDio(
        DioException(
          requestOptions: _opts(),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(ex, isA<ApiTimeoutException>());
    });

    test('connectionError maps to ApiNetworkException', () {
      final ApiException ex = ApiException.fromDio(
        DioException(
          requestOptions: _opts(),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(ex, isA<ApiNetworkException>());
    });

    test('unknown with SocketException maps to ApiNetworkException', () {
      final ApiException ex = ApiException.fromDio(
        DioException(
          requestOptions: _opts(),
          type: DioExceptionType.unknown,
          error: const SocketException('No internet'),
        ),
      );
      expect(ex, isA<ApiNetworkException>());
    });

    test('unknown without SocketException maps to ApiUnknownException', () {
      final ApiException ex = ApiException.fromDio(
        DioException(
          requestOptions: _opts(),
          type: DioExceptionType.unknown,
          error: 'something else',
        ),
      );
      expect(ex, isA<ApiUnknownException>());
    });

    test('cancel maps to ApiUnknownException with "Request cancelled"', () {
      final ApiException ex = ApiException.fromDio(
        DioException(requestOptions: _opts(), type: DioExceptionType.cancel),
      );
      expect(ex, isA<ApiUnknownException>());
      expect(ex.message, 'Request cancelled');
    });

    test('badResponse 401 maps to ApiAuthException', () {
      final ApiException ex = ApiException.fromDio(_bad(401));
      expect(ex, isA<ApiAuthException>());
      expect(ex.statusCode, 401);
    });

    test('badResponse 403 maps to ApiAuthException', () {
      final ApiException ex = ApiException.fromDio(_bad(403));
      expect(ex, isA<ApiAuthException>());
      expect(ex.statusCode, 403);
    });

    test('badResponse 409 maps to ApiConflictException', () {
      final ApiException ex = ApiException.fromDio(
        _bad(
          409,
          body: {
            'success': false,
            'message': 'Order was already taken by another rider',
            'code': 'ORDER_ALREADY_TAKEN',
          },
        ),
      );
      expect(ex, isA<ApiConflictException>());
      expect(ex.statusCode, 409);
      expect(ex.message, 'Order was already taken by another rider');
      expect(ex.backendCode, 'ORDER_ALREADY_TAKEN');
    });

    test('badResponse 500 maps to ApiServerException', () {
      final ApiException ex = ApiException.fromDio(_bad(500));
      expect(ex, isA<ApiServerException>());
      expect(ex.statusCode, 500);
    });

    test('badResponse 503 maps to ApiServerException', () {
      final ApiException ex = ApiException.fromDio(_bad(503));
      expect(ex, isA<ApiServerException>());
    });

    test('badResponse 400 maps to ApiValidationException', () {
      final ApiException ex = ApiException.fromDio(
        _bad(
          400,
          body: {
            'success': false,
            'message': 'Phone is invalid',
            'code': 'INVALID_PHONE',
          },
        ),
      );
      expect(ex, isA<ApiValidationException>());
      expect(ex.statusCode, 400);
      expect(ex.message, 'Phone is invalid');
      expect(ex.backendCode, 'INVALID_PHONE');
    });

    test('badResponse 404 maps to ApiValidationException', () {
      final ApiException ex = ApiException.fromDio(_bad(404));
      expect(ex, isA<ApiValidationException>());
    });

    test('badResponse with no status maps to ApiUnknownException', () {
      final RequestOptions ro = _opts();
      final ApiException ex = ApiException.fromDio(
        DioException(
          requestOptions: ro,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(requestOptions: ro),
        ),
      );
      expect(ex, isA<ApiUnknownException>());
    });

    test('badCertificate maps to ApiNetworkException', () {
      final ApiException ex = ApiException.fromDio(
        DioException(
          requestOptions: _opts(),
          type: DioExceptionType.badCertificate,
        ),
      );
      expect(ex, isA<ApiNetworkException>());
    });

    test('envelope message is preferred over the default copy', () {
      final ApiException ex = ApiException.fromDio(
        _bad(
          409,
          body: {
            'success': false,
            'message': 'Custom backend conflict',
            'code': 'CONFLICT_X',
          },
        ),
      );
      expect(ex.message, 'Custom backend conflict');
      expect(ex.backendCode, 'CONFLICT_X');
    });
  });
}
