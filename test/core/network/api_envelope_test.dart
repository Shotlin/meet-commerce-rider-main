import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/network/api_envelope.dart';

/// Unit tests for [ApiEnvelope.fromJson] and [Pagination.fromJson].
///
/// Acceptance for Task 1.3:
/// - The envelope parses success-with-object, success-with-list,
///   success-with-null, and failure-with-code/message shapes.
/// - The `parseData` callback is tolerant of `Map`, `List`, and `null`.
/// - [Pagination] tolerates both camelCase `totalPages` and snake_case
///   `total_pages` for the totalPages field.
void main() {
  group('ApiEnvelope.fromJson', () {
    test('parses a success envelope with an object data field', () {
      final ApiEnvelope<Map<String, dynamic>> env =
          ApiEnvelope<Map<String, dynamic>>.fromJson(<String, dynamic>{
            'success': true,
            'message': 'OK',
            'data': <String, dynamic>{'id': 'abc', 'phone': '+919999999999'},
          }, (Object? raw) => Map<String, dynamic>.from(raw as Map));

      expect(env.success, isTrue);
      expect(env.message, 'OK');
      expect(env.data, isNotNull);
      expect(env.data!['id'], 'abc');
      expect(env.pagination, isNull);
      expect(env.code, isNull);
    });

    test('parses a success envelope with a list data field', () {
      final ApiEnvelope<List<int>> env = ApiEnvelope<List<int>>.fromJson(
        <String, dynamic>{
          'success': true,
          'message': 'Listed',
          'data': <int>[1, 2, 3],
          'pagination': <String, dynamic>{
            'page': 1,
            'limit': 20,
            'total': 3,
            'totalPages': 1,
          },
        },
        (Object? raw) => List<int>.from(raw as List<dynamic>),
      );

      expect(env.success, isTrue);
      expect(env.data, <int>[1, 2, 3]);
      expect(env.pagination, isNotNull);
      expect(env.pagination!.page, 1);
      expect(env.pagination!.total, 3);
      expect(env.pagination!.totalPages, 1);
    });

    test('parses a success envelope with null data tolerantly', () {
      final ApiEnvelope<String> env = ApiEnvelope<String>.fromJson(
        <String, dynamic>{
          'success': true,
          'message': 'No content',
          'data': null,
        },
        (Object? raw) => raw == null ? '' : raw.toString(),
      );

      expect(env.success, isTrue);
      expect(env.data, '');
    });

    test('parses a failure envelope and surfaces top-level code', () {
      final ApiEnvelope<Object?> env =
          ApiEnvelope<Object?>.fromJson(<String, dynamic>{
            'success': false,
            'message': 'Order was already taken by another rider',
            'code': 'ORDER_ALREADY_TAKEN',
            'data': null,
          }, (Object? raw) => raw);

      expect(env.success, isFalse);
      expect(env.message, 'Order was already taken by another rider');
      expect(env.code, 'ORDER_ALREADY_TAKEN');
      expect(env.data, isNull);
    });

    test('falls back to data.code when no top-level code is present', () {
      final ApiEnvelope<Object?> env = ApiEnvelope<Object?>.fromJson(
        <String, dynamic>{
          'success': false,
          'message': 'Validation failed',
          'data': <String, dynamic>{'code': 'INVALID_OTP'},
        },
        (Object? raw) => raw,
      );

      expect(env.success, isFalse);
      expect(env.code, 'INVALID_OTP');
    });

    test('top-level code wins when both are present', () {
      final ApiEnvelope<Object?> env = ApiEnvelope<Object?>.fromJson(
        <String, dynamic>{
          'success': false,
          'message': 'Conflict',
          'code': 'TOP',
          'data': <String, dynamic>{'code': 'NESTED'},
        },
        (Object? raw) => raw,
      );

      expect(env.code, 'TOP');
    });

    test('defaults success to false and message to empty when missing', () {
      final ApiEnvelope<Object?> env = ApiEnvelope<Object?>.fromJson(
        <String, dynamic>{},
        (Object? raw) => raw,
      );

      expect(env.success, isFalse);
      expect(env.message, '');
      expect(env.data, isNull);
      expect(env.code, isNull);
    });
  });

  group('Pagination.fromJson', () {
    test('parses a fully camelCase block', () {
      final Pagination p = Pagination.fromJson(<String, dynamic>{
        'page': 2,
        'limit': 25,
        'total': 100,
        'totalPages': 4,
      });

      expect(p.page, 2);
      expect(p.limit, 25);
      expect(p.total, 100);
      expect(p.totalPages, 4);
    });

    test('tolerates snake_case total_pages', () {
      final Pagination p = Pagination.fromJson(<String, dynamic>{
        'page': 1,
        'limit': 10,
        'total': 53,
        'total_pages': 6,
      });

      expect(p.totalPages, 6);
    });

    test('camelCase totalPages wins when both are present', () {
      final Pagination p = Pagination.fromJson(<String, dynamic>{
        'page': 1,
        'limit': 10,
        'total': 53,
        'totalPages': 6,
        'total_pages': 99,
      });

      expect(p.totalPages, 6);
    });

    test('parses numeric strings leniently', () {
      final Pagination p = Pagination.fromJson(<String, dynamic>{
        'page': '3',
        'limit': '50',
        'total': '150',
        'totalPages': '3',
      });

      expect(p.page, 3);
      expect(p.limit, 50);
      expect(p.total, 150);
      expect(p.totalPages, 3);
    });

    test('defaults missing fields to zero', () {
      final Pagination p = Pagination.fromJson(<String, dynamic>{});
      expect(p.page, 0);
      expect(p.limit, 0);
      expect(p.total, 0);
      expect(p.totalPages, 0);
    });
  });
}
