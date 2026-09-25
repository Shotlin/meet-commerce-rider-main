import 'dart:io';

import '../../../core/utils/app_logger.dart';
import '../domain/rider_document.dart';
import 'documents_api.dart';

/// Application-facing repository for rider document operations.
///
/// `DocumentsRepository` is a thin pass-through over [DocumentsApi]:
/// the API client already owns image compression and upload, so the
/// repository's job is to centralise logging and provide a stable
/// surface for the controller. Keeping a repository layer (even a
/// thin one) means that future cross-cutting concerns — caching,
/// retry policy, multi-source aggregation — have an obvious home
/// without having to refactor every controller call site.
class DocumentsRepository {
  /// Wires the repository to its [api].
  DocumentsRepository(this._api);

  final DocumentsApi _api;

  /// Returns the rider's current documents.
  ///
  /// Empty for a brand-new rider; the live backend's seed rider has
  /// `{ "documents": [] }` and the API surface treats that as success.
  Future<List<RiderDocument>> list() async {
    final List<RiderDocument> docs = await _api.list();
    AppLogger.debug(
      LogTopic.state,
      'DocumentsRepository.list: fetched ${docs.length} document(s)',
    );
    return docs;
  }

  /// Compresses [file], uploads it for [type], and returns the parsed
  /// [RiderDocument] from the server's response.
  Future<RiderDocument> upload(RiderDocumentType type, File file) async {
    AppLogger.debug(
      LogTopic.state,
      'DocumentsRepository.upload: type=${type.wire} path=${file.path}',
    );
    final RiderDocument doc = await _api.upload(type, file);
    AppLogger.info(
      LogTopic.state,
      'DocumentsRepository.upload: uploaded ${type.wire} -> ${doc.status}',
    );
    return doc;
  }

  /// Returns the upload progress stream for [type] backed by [file].
  Stream<double> uploadWithProgress(RiderDocumentType type, File file) {
    AppLogger.debug(
      LogTopic.state,
      'DocumentsRepository.uploadWithProgress: type=${type.wire}',
    );
    return _api.uploadWithProgress(type, file);
  }
}
