import 'package:flutter/foundation.dart';

/// Wraps the standard envelope returned by every Meet Commerce REST endpoint.
///
/// The live backend always responds with:
///
/// ```json
/// {
///   "success": true | false,
///   "message": "<human readable>",
///   "data": <object | array | null>,
///   "code": "<ERROR_CODE>",        // optional, present on failures
///   "errors": [{...}],              // optional, validation errors
///   "pagination": { ... }           // optional, paginated routes
/// }
/// ```
///
/// `ApiEnvelope<T>` is generic over the parsed payload. Pass a `parseData`
/// function that knows how to map the inner `data` JSON to your domain
/// type. For routes that return a bare array under `data` (e.g.
/// `/delivery/orders`), the caller can use a list parser; for routes
/// whose `data` is `null` on success (e.g. `/delivery/location`), pass a
/// parser that returns `void` / `null`.
///
/// The error-`code` lookup falls back to `data.code` when the top-level
/// envelope omits it. A few backend routes nest the code inside `data`
/// for failure responses; preferring the top-level value when both are
/// present matches what the live backend does on routes we have probed.
@immutable
class ApiEnvelope<T> {
  /// Constructs an envelope explicitly.
  const ApiEnvelope({
    required this.success,
    required this.message,
    this.data,
    this.code,
    this.errors,
    this.pagination,
  });

  /// Builds an envelope from a decoded JSON map.
  ///
  /// [parseData] is invoked only when [json] looks like a successful
  /// response with non-null `data`; on failures the envelope still
  /// captures `success`, `message`, `code`, and `errors` so error
  /// translation can read them downstream.
  factory ApiEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(Object?) parseData,
  ) {
    final bool success = (json['success'] as bool?) ?? false;
    final String message = (json['message'] as String?) ?? '';
    final Object? rawData = json['data'];
    final String? code =
        (json['code'] as String?) ?? _readNestedDataCode(rawData);
    final List<Map<String, dynamic>>? errors = _readErrors(json['errors']);
    final Pagination? pagination = _readPagination(json['pagination']);

    if (success) {
      // Always invoke the parser, even when data is null, so callers
      // that handle the "no content" success case (e.g. /delivery/location)
      // can map null to whatever sentinel they need.
      return ApiEnvelope<T>(
        success: true,
        message: message,
        data: parseData(rawData),
        code: code,
        errors: errors,
        pagination: pagination,
      );
    }
    return ApiEnvelope<T>(
      success: success,
      message: message,
      data: null,
      code: code,
      errors: errors,
      pagination: pagination,
    );
  }

  /// Whether the request was processed successfully by the backend.
  final bool success;

  /// Human-readable status / error message returned by the backend.
  final String message;

  /// Parsed payload. Null when the call failed or `data` was null.
  final T? data;

  /// Backend error code (e.g. `ORDER_NOT_AVAILABLE`, `INVALID_OTP`).
  /// Resolved from the top-level envelope first, then from `data.code`
  /// as a fallback so failure shapes that nest the code remain readable.
  final String? code;

  /// Validation-error rows when [code] is `VALIDATION_ERROR`.
  final List<Map<String, dynamic>>? errors;

  /// Pagination metadata when present at the envelope level.
  final Pagination? pagination;

  static String? _readNestedDataCode(Object? rawData) {
    if (rawData is Map) {
      final Object? nested = rawData['code'];
      if (nested is String) return nested;
    }
    return null;
  }

  static List<Map<String, dynamic>>? _readErrors(Object? raw) {
    if (raw is! List) return null;
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map<Map<String, dynamic>>(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  static Pagination? _readPagination(Object? raw) {
    if (raw is! Map) return null;
    return Pagination.fromJson(Map<String, dynamic>.from(raw));
  }
}

/// Pagination metadata returned at the envelope level on routes that use
/// the canonical wrapper (`/delivery/payouts`).
///
/// `Pagination.fromJson` is intentionally tolerant: it accepts both
/// camelCase `totalPages` and snake_case `total_pages`, parses numeric
/// strings (`"3"`) into ints, and defaults missing fields to 0 so a
/// partial envelope never throws.
@immutable
class Pagination {
  /// Constructs a pagination block explicitly.
  const Pagination({
    required this.page,
    required this.totalPages,
    required this.total,
    this.limit = 0,
  });

  /// Current page number (1-indexed).
  final int page;

  /// Total number of pages.
  final int totalPages;

  /// Total number of items across all pages.
  final int total;

  /// Echoed page size. The live backend currently does NOT echo this
  /// value, so callers should treat it as best-effort. Defaults to 0
  /// when missing.
  final int limit;

  /// Lenient parser. Accepts both `totalPages` and `total_pages`,
  /// numeric strings, and missing fields (defaulting to 0).
  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      page: _readInt(json['page']) ?? 0,
      totalPages:
          _readInt(json['totalPages']) ?? _readInt(json['total_pages']) ?? 0,
      total: _readInt(json['total']) ?? 0,
      limit: _readInt(json['limit']) ?? 0,
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
