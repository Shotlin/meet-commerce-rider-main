import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/image_compressor.dart';
import '../domain/rider_document.dart';

/// Transport-level wrapper around the rider document endpoints.
///
/// `DocumentsApi` knows how to:
/// - List the rider's currently-uploaded documents
///   (`GET /delivery/documents`).
/// - Compress a file with [ImageCompressor] and upload it as
///   `multipart/form-data` to `POST /delivery/documents/:type`
///   (R4.4-R4.5).
/// - Surface upload progress as a 0..1 [Stream<double>] for the
///   document upload screen's progress bar.
///
/// The live backend responds to `GET /delivery/documents` with
/// `{ "data": { "documents": [] } }` for a brand-new rider; the empty
/// array is the expected shape and is treated as success here.
class DocumentsApi {
  /// Wraps the supplied [client] and uses [compressor] to shrink files
  /// before upload.
  DocumentsApi({required ApiClient client, required ImageCompressor compressor})
    : _client = client,
      _compressor = compressor;

  final ApiClient _client;
  final ImageCompressor _compressor;

  /// Fetches the rider's current documents.
  ///
  /// Each entry in `data.documents` is run through
  /// [RiderDocument.fromJson]; entries with an unknown `type` string
  /// are skipped rather than crashing the list, because future backend
  /// changes may add new document types we don't yet model.
  Future<List<RiderDocument>> list() async {
    final ApiEnvelope<List<RiderDocument>> envelope = await _client
        .get<List<RiderDocument>>(
          '/delivery/documents',
          parseData: _parseListPayload,
        );
    return envelope.data ?? const <RiderDocument>[];
  }

  /// Decodes the `data` payload from `GET /delivery/documents`.
  ///
  /// The live backend returns `{ "documents": [] }` even when the
  /// rider has no uploads. Anything else (a top-level array, a null
  /// `documents` key, etc.) is treated as an empty list and logged
  /// at debug rather than thrown, because the rider approval screen
  /// can recover by showing all six rows as `missing`.
  static List<RiderDocument> _parseListPayload(Object? raw) {
    if (raw is! Map) {
      return const <RiderDocument>[];
    }
    final Object? docs = raw['documents'];
    if (docs is! List) {
      return const <RiderDocument>[];
    }
    final List<RiderDocument> result = <RiderDocument>[];
    for (final Object? item in docs) {
      if (item is! Map) continue;
      try {
        result.add(RiderDocument.fromJson(Map<String, dynamic>.from(item)));
      } on FormatException catch (e) {
        AppLogger.debug(
          LogTopic.parse,
          'DocumentsApi.list: skipping unknown document entry: $e',
        );
      }
    }
    return List<RiderDocument>.unmodifiable(result);
  }

  /// Compresses [file] and uploads it to
  /// `POST /delivery/documents/:type` as `multipart/form-data` with a
  /// single field named `file` (R4.5).
  ///
  /// Returns the parsed [RiderDocument] from the server response. The
  /// live backend's success response shape for this route is not yet
  /// pinned down (no document has been uploaded against the seed
  /// rider); the parser accepts the document directly under `data`,
  /// nested under `data.document`, or falls back to a synthetic
  /// `{ type, status: pending }` echo so the call still succeeds and
  /// the controller can re-fetch the canonical state via [list].
  Future<RiderDocument> upload(RiderDocumentType type, File file) async {
    final File compressed = await _compressor.compress(file);
    final FormData formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(
        compressed.path,
        filename: '${type.wire}.jpg',
      ),
    });

    final Response<dynamic> response = await _client.dio.post<dynamic>(
      '/delivery/documents/${type.wire}',
      data: formData,
    );

    return _parseUploadResponse(type, response.data);
  }

  /// Compresses [file] and uploads it, emitting the upload progress
  /// as a fraction in `[0.0, 1.0]` (R4.5).
  ///
  /// The stream emits one final value at exactly `1.0` once the
  /// upload completes, even when Dio's content-length-based progress
  /// reporting is incomplete (some proxies omit `Content-Length`).
  /// The stream closes after the final emission. If the upload throws,
  /// the error propagates through the stream so callers can use a
  /// single `await for` loop with a try/catch.
  ///
  /// The compressed [RiderDocument] response itself is NOT carried
  /// through this stream; callers that need it should call [upload]
  /// instead. The progress stream is intentionally narrow because the
  /// rider approval flow re-fetches the document list after a
  /// successful upload anyway.
  Stream<double> uploadWithProgress(RiderDocumentType type, File file) {
    final StreamController<double> controller =
        StreamController<double>.broadcast();

    Future<void> run() async {
      try {
        final File compressed = await _compressor.compress(file);
        final FormData formData = FormData.fromMap(<String, dynamic>{
          'file': await MultipartFile.fromFile(
            compressed.path,
            filename: '${type.wire}.jpg',
          ),
        });

        await _client.dio.post<dynamic>(
          '/delivery/documents/${type.wire}',
          data: formData,
          onSendProgress: (int sent, int total) {
            if (controller.isClosed) return;
            if (total <= 0) return;
            final double fraction = sent / total;
            final double clamped = fraction.isNaN
                ? 0
                : fraction.clamp(0.0, 1.0);
            controller.add(clamped);
          },
        );

        if (!controller.isClosed) {
          controller.add(1.0);
          await controller.close();
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      }
    }

    // Start the upload eagerly so the caller can listen at any time
    // without missing intermediate progress events.
    unawaited(run());
    return controller.stream;
  }

  /// Decodes the response body returned by `POST /delivery/documents/:type`.
  ///
  /// The live backend hasn't been observed returning a real document
  /// yet, so we accept three shapes:
  ///
  /// 1. `data` is the document map directly.
  /// 2. `data.document` is the document map.
  /// 3. Anything else falls back to a synthetic
  ///    `{ type, status: pending }` echo. The caller (the repository)
  ///    typically re-fetches the canonical list after a successful
  ///    upload, so the synthetic echo is just enough to keep the UI
  ///    responsive in the meantime.
  RiderDocument _parseUploadResponse(RiderDocumentType type, Object? raw) {
    if (raw is! Map) {
      return RiderDocument(type: type, status: RiderDocumentStatus.pending);
    }
    final Map<String, dynamic> body = Map<String, dynamic>.from(raw);
    final Object? data = body['data'];

    Map<String, dynamic>? docJson;
    if (data is Map) {
      final Map<String, dynamic> dataMap = Map<String, dynamic>.from(data);
      final Object? nested = dataMap['document'];
      if (nested is Map) {
        docJson = Map<String, dynamic>.from(nested);
      } else if (dataMap.containsKey('type') ||
          dataMap.containsKey('document_type') ||
          dataMap.containsKey('status') ||
          dataMap.containsKey('url')) {
        docJson = dataMap;
      }
    }

    if (docJson == null) {
      return RiderDocument(type: type, status: RiderDocumentStatus.pending);
    }
    // Ensure the `type` field is populated so fromJson can resolve it
    // even when the backend omits it in the upload echo.
    docJson.putIfAbsent('type', () => type.wire);
    try {
      return RiderDocument.fromJson(docJson);
    } on FormatException {
      return RiderDocument(type: type, status: RiderDocumentStatus.pending);
    }
  }
}
