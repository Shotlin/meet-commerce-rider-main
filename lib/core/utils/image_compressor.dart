import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_constants.dart';
import 'app_logger.dart';

/// JPEG image compressor used by both the rider document onboarding
/// flow (R4.4) and the proof-photo delivery flow (R15.2).
///
/// Compression parameters come from [AppConstants]:
/// longest edge [AppConstants.imageMaxLongestEdgePx] (1600 px) and
/// JPEG quality [AppConstants.imageJpegQuality] (80). Both flows hit
/// the same multipart upload pipeline, so keeping the compression
/// rules in one class avoids drift between rider documents and proof
/// photos.
///
/// The compressed bytes are written under [getTemporaryDirectory] with
/// a unique filename so concurrent uploads (e.g. retrying a failed
/// upload while the original is still being garbage-collected) don't
/// stomp each other. The OS purges the temp directory between
/// sessions, so we don't accumulate stale uploads.
///
/// Tests can pass [tempDirOverride] to redirect the output directory
/// to a deterministic location without mocking `path_provider`.
class ImageCompressor {
  /// Builds a compressor.
  ///
  /// [tempDirOverride] is optional and only used by tests; production
  /// code uses [getTemporaryDirectory] from `path_provider`.
  ImageCompressor({Directory? tempDirOverride})
    : _tempDirOverride = tempDirOverride;

  final Directory? _tempDirOverride;

  /// Compresses [source] to a JPEG bounded by
  /// [AppConstants.imageMaxLongestEdgePx] on its longest edge with
  /// quality [AppConstants.imageJpegQuality].
  ///
  /// Returns the compressed [File]. If the underlying compression
  /// returns null (the platform plugin failed to decode the input),
  /// [source] is returned unchanged so the upload can still proceed
  /// rather than silently dropping.
  ///
  /// The output file lives under the temp directory with a unique
  /// name combining the original basename and a high-resolution
  /// timestamp, so multiple in-flight compressions never collide.
  Future<File> compress(File source) async {
    final Directory tempDir = _tempDirOverride ?? await getTemporaryDirectory();
    final String baseName = p.basenameWithoutExtension(source.path);
    final int unique = DateTime.now().microsecondsSinceEpoch;
    final String outPath = p.join(
      tempDir.path,
      'compressed_${baseName}_$unique.jpg',
    );

    final int originalBytes = await _safeLength(source);

    final XFile? result = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      outPath,
      minWidth: AppConstants.imageMaxLongestEdgePx,
      minHeight: AppConstants.imageMaxLongestEdgePx,
      quality: AppConstants.imageJpegQuality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );

    if (result == null) {
      AppLogger.warn(
        LogTopic.state,
        'ImageCompressor: compression returned null; '
        'falling back to original (${originalBytes}B)',
      );
      return source;
    }

    final File compressed = File(result.path);
    final int compressedBytes = await _safeLength(compressed);
    AppLogger.debug(
      LogTopic.state,
      'ImageCompressor: ${baseName} '
      'original=${originalBytes}B compressed=${compressedBytes}B',
    );
    return compressed;
  }

  /// Reads the length of [file] without throwing. Used purely for
  /// logging; a missing or unreadable file simply logs as `-1`.
  Future<int> _safeLength(File file) async {
    try {
      return await file.length();
    } catch (_) {
      return -1;
    }
  }
}
