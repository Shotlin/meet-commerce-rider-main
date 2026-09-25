import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/network/api_client.dart';
import 'package:meet_commerce_rider_main/core/utils/image_compressor.dart';
import 'package:meet_commerce_rider_main/features/onboarding/data/documents_api.dart';
import 'package:meet_commerce_rider_main/features/onboarding/domain/rider_document.dart';

/// Test-only [ImageCompressor] that returns the input file unchanged.
///
/// Subclasses [ImageCompressor] purely to avoid touching the platform
/// `flutter_image_compress` plugin in unit tests. The [callCount]
/// counter lets tests assert that the compressor is on the upload
/// path (R4.4 requires compression before every upload).
class _PassthroughCompressor extends ImageCompressor {
  _PassthroughCompressor() : super(tempDirOverride: Directory.systemTemp);

  int callCount = 0;

  @override
  Future<File> compress(File source) async {
    callCount++;
    return source;
  }
}

/// Records each request the test sees so we can assert URL, method,
/// content type, multipart fields, etc. The adapter never calls real
/// HTTP — it returns canned responses keyed by path so tests are
/// deterministic.
class _RecordingAdapter implements HttpClientAdapter {
  /// JSON body to return for the next call to a given path.
  ///
  /// Defaults to `{ success: true, data: null }` for any path that
  /// isn't pre-registered, which keeps the multipart test focused on
  /// what was sent rather than what came back.
  final Map<String, Object?> dataByPath = <String, Object?>{};

  /// Status code per path. Defaults to 200.
  final Map<String, int> statusByPath = <String, int>{};

  /// One [_RecordedRequest] per request seen, in arrival order.
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Buffer the request body so the test can inspect what Dio
    // actually serialized (multipart bytes are otherwise lost).
    final List<int> bodyBytes = <int>[];
    if (requestStream != null) {
      await for (final Uint8List chunk in requestStream) {
        bodyBytes.addAll(chunk);
      }
    }

    requests.add(
      _RecordedRequest(
        method: options.method,
        path: options.path,
        contentType: options.headers[Headers.contentTypeHeader] as String?,
        bodyBytes: bodyBytes,
      ),
    );

    final int status = statusByPath[options.path] ?? 200;
    final Object? data = dataByPath[options.path];
    final Map<String, dynamic> body = <String, dynamic>{
      'success': status >= 200 && status < 300,
      'message': 'ok',
      'data': data,
    };

    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

class _RecordedRequest {
  _RecordedRequest({
    required this.method,
    required this.path,
    required this.contentType,
    required this.bodyBytes,
  });

  final String method;
  final String path;
  final String? contentType;
  final List<int> bodyBytes;

  String get bodyAsLatin1 => latin1.decode(bodyBytes, allowInvalid: true);
}

/// Builds an [ApiClient] whose Dio is wired to [adapter].
ApiClient _buildClient(_RecordingAdapter adapter) {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: 'https://example.test',
      contentType: 'application/json',
      validateStatus: (int? status) =>
          status != null && status >= 200 && status < 600,
    ),
  )..httpClientAdapter = adapter;
  return ApiClient(dio);
}

/// Writes a tiny placeholder file so multipart upload tests have
/// something to stream. The bytes don't need to be a real JPEG —
/// `_PassthroughCompressor` doesn't decode them.
Future<File> _writeTempFile(String name) async {
  final File file = File(
    '${Directory.systemTemp.path}/${name}_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  return file;
}

void main() {
  group('DocumentsApi.list', () {
    test(
      'returns an empty list for the live backend\'s empty response',
      () async {
        // Live backend returns { documents: [] } for a brand-new rider.
        final _RecordingAdapter adapter = _RecordingAdapter()
          ..dataByPath['/delivery/documents'] = <String, dynamic>{
            'documents': <Object>[],
          };
        final ApiClient client = _buildClient(adapter);
        final DocumentsApi api = DocumentsApi(
          client: client,
          compressor: _PassthroughCompressor(),
        );

        final List<RiderDocument> docs = await api.list();

        expect(docs, isEmpty);
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.method, 'GET');
        expect(adapter.requests.single.path, '/delivery/documents');
      },
    );

    test('parses populated documents and skips unknown types', () async {
      final _RecordingAdapter adapter = _RecordingAdapter()
        ..dataByPath['/delivery/documents'] = <String, dynamic>{
          'documents': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'photo',
              'status': 'APPROVED',
              'url': 'https://cdn.example.com/photo.jpg',
            },
            <String, dynamic>{'type': 'license', 'status': 'PENDING'},
            // Unknown type should be skipped, not crash the list.
            <String, dynamic>{
              'type': 'something_we_dont_know',
              'status': 'APPROVED',
            },
          ],
        };
      final ApiClient client = _buildClient(adapter);
      final DocumentsApi api = DocumentsApi(
        client: client,
        compressor: _PassthroughCompressor(),
      );

      final List<RiderDocument> docs = await api.list();

      expect(docs, hasLength(2));
      expect(docs[0].type, RiderDocumentType.photo);
      expect(docs[0].status, RiderDocumentStatus.approved);
      expect(docs[1].type, RiderDocumentType.drivingLicense);
      expect(docs[1].status, RiderDocumentStatus.pending);
    });
  });

  group('DocumentsApi.upload', () {
    test(
      'POSTs multipart to /delivery/documents/<wire> with a `file` field',
      () async {
        final _RecordingAdapter adapter = _RecordingAdapter()
          ..dataByPath['/delivery/documents/license'] = <String, dynamic>{
            'type': 'license',
            'status': 'PENDING',
          };
        final ApiClient client = _buildClient(adapter);
        final _PassthroughCompressor compressor = _PassthroughCompressor();
        final DocumentsApi api = DocumentsApi(
          client: client,
          compressor: compressor,
        );

        final File source = await _writeTempFile('upload_dl');
        try {
          final RiderDocument doc = await api.upload(
            RiderDocumentType.drivingLicense,
            source,
          );

          expect(doc.type, RiderDocumentType.drivingLicense);
          expect(doc.status, RiderDocumentStatus.pending);

          // Compression must have run before the upload (R4.4).
          expect(compressor.callCount, 1);

          // Exactly one request, hitting the type-specific path.
          expect(adapter.requests, hasLength(1));
          final _RecordedRequest req = adapter.requests.single;
          expect(req.method, 'POST');
          expect(req.path, '/delivery/documents/license');
          expect(req.contentType, contains('multipart/form-data'));

          // The multipart payload must include a `file` field with the
          // upload's filename. Boundary lines are easier to assert against
          // the latin1 decoding because they include literal CRLFs.
          final String body = req.bodyAsLatin1;
          expect(body, contains('name="file"'));
          // The filename is derived from the wire value
          // (`documents_api.dart`: '${type.wire}.jpg'), so it must be the
          // backend-legal segment here, not a legacy alias.
          expect(body, contains('filename="license.jpg"'));
        } finally {
          if (await source.exists()) await source.delete();
        }
      },
    );

    test(
      'uses the wire string for each document type in the URL path',
      () async {
        for (final RiderDocumentType type in RiderDocumentType.values) {
          final _RecordingAdapter adapter = _RecordingAdapter()
            ..dataByPath['/delivery/documents/${type.wire}'] =
                <String, dynamic>{'type': type.wire, 'status': 'PENDING'};
          final ApiClient client = _buildClient(adapter);
          final DocumentsApi api = DocumentsApi(
            client: client,
            compressor: _PassthroughCompressor(),
          );

          final File source = await _writeTempFile('upload_${type.wire}');
          try {
            final RiderDocument doc = await api.upload(type, source);
            expect(doc.type, type);
            expect(
              adapter.requests.single.path,
              '/delivery/documents/${type.wire}',
            );
          } finally {
            if (await source.exists()) await source.delete();
          }
        }
      },
    );
  });

  group('DocumentsApi.uploadWithProgress', () {
    test(
      'emits a final 1.0 progress and closes the stream on success',
      () async {
        final _RecordingAdapter adapter = _RecordingAdapter()
          ..dataByPath['/delivery/documents/photo'] = <String, dynamic>{
            'type': 'photo',
            'status': 'PENDING',
          };
        final ApiClient client = _buildClient(adapter);
        final DocumentsApi api = DocumentsApi(
          client: client,
          compressor: _PassthroughCompressor(),
        );

        final File source = await _writeTempFile('upload_photo_progress');
        try {
          final List<double> progress = <double>[];
          await api
              .uploadWithProgress(RiderDocumentType.photo, source)
              .listen(progress.add)
              .asFuture<void>();

          expect(progress, isNotEmpty);
          expect(progress.last, 1.0);
          for (final double p in progress) {
            expect(p, inInclusiveRange(0.0, 1.0));
          }
        } finally {
          if (await source.exists()) await source.delete();
        }
      },
    );
  });
}
