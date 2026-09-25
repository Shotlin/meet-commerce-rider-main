import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../data/documents_repository.dart';
import '../domain/rider_document.dart';

/// Application-layer controller for the rider document onboarding
/// flow (R4.1-R4.7).
///
/// Holds the canonical list of [RiderDocument]s and per-type upload
/// progress / error state. The UI reads three streams of state via
/// `Listenable`-style getters and reacts to changes through the
/// [ChangeNotifier] contract.
///
/// Why `ChangeNotifier` (via `flutter_riverpod/legacy.dart`)? The
/// existing rider approval and document upload screens already build
/// against `ChangeNotifierProvider`; staying on that contract keeps
/// the upload flow consistent with the rest of the app and avoids
/// two parallel idioms in the same feature.
class DocumentsController extends ChangeNotifier {
  /// Builds a controller backed by [repository].
  DocumentsController({required DocumentsRepository repository})
    : _repository = repository;

  final DocumentsRepository _repository;

  List<RiderDocument> _documents = const <RiderDocument>[];
  bool _isLoading = false;
  String? _listErrorMessage;
  final Map<RiderDocumentType, double> _uploadProgress =
      <RiderDocumentType, double>{};
  final Map<RiderDocumentType, String> _uploadErrors =
      <RiderDocumentType, String>{};
  final Map<RiderDocumentType, StreamSubscription<double>> _activeUploads =
      <RiderDocumentType, StreamSubscription<double>>{};
  bool _disposed = false;

  /// Latest list of rider documents, in the order returned by the
  /// backend. Empty until [refresh] is called.
  List<RiderDocument> get documents => _documents;

  /// True while [refresh] is in flight.
  bool get isLoading => _isLoading;

  /// Last error message from a failed [refresh] call. Cleared on the
  /// next successful refresh.
  String? get listErrorMessage => _listErrorMessage;

  /// Per-type upload progress in `[0.0, 1.0]`. Entries are removed
  /// once the upload completes (success or failure) so the UI only
  /// shows progress bars for in-flight uploads.
  Map<RiderDocumentType, double> get uploadProgress =>
      Map<RiderDocumentType, double>.unmodifiable(_uploadProgress);

  /// Per-type upload error message. Entries are cleared automatically
  /// when the rider retries an upload for the same type.
  Map<RiderDocumentType, String> get uploadErrors =>
      Map<RiderDocumentType, String>.unmodifiable(_uploadErrors);

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Refreshes the document list from the backend.
  ///
  /// Sets [isLoading] to `true` for the duration of the call. On
  /// success, [documents] is replaced with the new list and
  /// [listErrorMessage] is cleared. On failure, the previous list is
  /// preserved and [listErrorMessage] is set so the UI can render
  /// an inline retry control.
  Future<void> refresh() async {
    _isLoading = true;
    _listErrorMessage = null;
    _safeNotify();
    try {
      final List<RiderDocument> docs = await _repository.list();
      if (_disposed) return;
      _documents = docs;
    } catch (e, st) {
      AppLogger.warn(
        LogTopic.state,
        'DocumentsController.refresh failed',
        error: e,
        stackTrace: st,
      );
      if (_disposed) return;
      _listErrorMessage = e.toString();
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _safeNotify();
      }
    }
  }

  /// Compresses and uploads [file] for [type], streaming progress into
  /// [uploadProgress] and any failure into [uploadErrors].
  ///
  /// On success, [refresh] is called automatically so the
  /// [documents] list reflects the new server state. If a previous
  /// upload for the same [type] is still in flight, it is cancelled
  /// before the new upload starts to avoid two competing progress
  /// streams on the same type.
  Future<void> upload(RiderDocumentType type, File file) async {
    // Cancel any in-flight upload for the same type so its progress
    // events can't bleed into the new upload's UI state.
    final StreamSubscription<double>? previous = _activeUploads.remove(type);
    await previous?.cancel();

    _uploadErrors.remove(type);
    _uploadProgress[type] = 0.0;
    _safeNotify();

    final Completer<void> done = Completer<void>();
    final Stream<double> progressStream = _repository.uploadWithProgress(
      type,
      file,
    );

    final StreamSubscription<double> subscription = progressStream.listen(
      (double progress) {
        if (_disposed) return;
        _uploadProgress[type] = progress;
        _safeNotify();
      },
      onError: (Object error, StackTrace st) {
        AppLogger.warn(
          LogTopic.state,
          'DocumentsController.upload(${type.wire}) failed',
          error: error,
          stackTrace: st,
        );
        if (_disposed) {
          if (!done.isCompleted) done.complete();
          return;
        }
        _uploadProgress.remove(type);
        _uploadErrors[type] = error.toString();
        _activeUploads.remove(type);
        _safeNotify();
        if (!done.isCompleted) done.complete();
      },
      onDone: () async {
        if (_disposed) {
          if (!done.isCompleted) done.complete();
          return;
        }
        _uploadProgress.remove(type);
        _activeUploads.remove(type);
        _safeNotify();
        // Re-fetch the list so the new document's status (which the
        // server determines) is reflected on the approval screen.
        await refresh();
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    _activeUploads[type] = subscription;
    return done.future;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final StreamSubscription<double> sub in _activeUploads.values) {
      // Fire-and-forget: the controller is being torn down; we don't
      // need to await each cancellation.
      unawaited(sub.cancel());
    }
    _activeUploads.clear();
    super.dispose();
  }
}
