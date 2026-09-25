import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Disk-cached, OSM-friendly tile provider.
///
/// Replaces Google's hosted tile pipeline:
/// 1. First lookup hits a small in-memory LRU.
/// 2. On a memory miss, the on-disk cache is consulted (a flat
///    directory of `<z>_<x>_<y>.png` files under
///    `<app-cache>/rider_osm_interim`).
/// 3. On a disk miss, the tile is fetched from [tileUrlTemplate] over
///    HTTP with the `User-Agent` header — OSM bans empty / generic
///    UAs.
/// 4. On any HTTP / I/O failure the provider serves a 256x256 neutral
///    grey placeholder so the map never goes blank.
///
/// The on-disk cache is **size-bounded**: writes that push the
/// directory above [maxBytes] (default 100 MB) trigger an LRU sweep
/// that deletes the oldest files until we are back under budget.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({
    required this.userAgent,
    String? tileUrlTemplate,
    http.Client? httpClient,
    int maxBytes = _defaultMaxBytes,
    int memoryCacheSize = _defaultMemoryCacheSize,
  }) : _httpClient = httpClient ?? http.Client(),
       _tileUrlTemplate = tileUrlTemplate ?? _defaultTileUrlTemplate,
       _maxBytes = maxBytes,
       _memoryCacheSize = memoryCacheSize;

  /// Default OpenStreetMap raster endpoint.
  static const String _defaultTileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// 100 MB on-disk budget for the tile cache.
  static const int _defaultMaxBytes = 100 * 1024 * 1024;

  /// Up to 256 tiles cached in RAM (~16 MB at 64 KB / tile worst case).
  static const int _defaultMemoryCacheSize = 256;

  final String userAgent;
  final String _tileUrlTemplate;
  final http.Client _httpClient;
  final int _maxBytes;
  final int _memoryCacheSize;

  Future<Directory>? _cacheDirFuture;

  // Tiny LRU keyed by `z/x/y` cache key. Insertion order = recency.
  final LinkedHashMap<String, Uint8List> _memoryCache =
      LinkedHashMap<String, Uint8List>();

  // De-duplicate concurrent downloads of the same tile using
  // completers so the analyzer doesn't flag stored futures as
  // unawaited. The single owner that calls `_fetch` resolves the
  // completer; all other callers await the same completer's future.
  final Map<String, Completer<Uint8List>> _inflight =
      <String, Completer<Uint8List>>{};

  // Cached grey placeholder bytes.
  Uint8List? _placeholderBytes;

  // Concurrency cap of 4 tiles at a time so we don't hammer OSM.
  static const int _maxConcurrent = 4;
  int _activeDownloads = 0;
  final List<Completer<void>> _waitingSlots = <Completer<void>>[];

  @override
  ImageProvider<Object> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) {
    return _CachedTileImage(provider: this, coordinates: coordinates);
  }

  /// Loads a single tile, returning bytes (real or placeholder).
  Future<Uint8List> loadTile(TileCoordinates c) async {
    final String key = '${c.z}/${c.x}/${c.y}';

    // 1. Memory.
    final Uint8List? cached = _memoryCache.remove(key);
    if (cached != null) {
      _memoryCache[key] = cached; // mark recent
      return cached;
    }

    // 2. Disk.
    try {
      final Directory dir = await _ensureCacheDir();
      final File f = File(p.join(dir.path, '${c.z}_${c.x}_${c.y}.png'));
      if (await f.exists()) {
        final Uint8List bytes = await f.readAsBytes();
        _rememberInMemory(key, bytes);
        return bytes;
      }
    } catch (_) {
      // Disk errors fall through to network.
    }

    // 3. Network (deduplicated via completers).
    final Completer<Uint8List>? existing = _inflight[key];
    if (existing != null) {
      return existing.future;
    }
    final Completer<Uint8List> completer = Completer<Uint8List>();
    _inflight[key] = completer;
    try {
      final Uint8List bytes = await _fetch(c, key);
      completer.complete(bytes);
      return bytes;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _inflight.remove(key);
    }
  }

  Future<Uint8List> _fetch(TileCoordinates c, String key) async {
    await _acquireSlot();
    try {
      final String url = _tileUrlTemplate
          .replaceAll('{z}', c.z.toString())
          .replaceAll('{x}', c.x.toString())
          .replaceAll('{y}', c.y.toString());
      final http.Response resp = await _httpClient.get(
        Uri.parse(url),
        headers: <String, String>{'User-Agent': userAgent},
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final Uint8List bytes = resp.bodyBytes;
        _rememberInMemory(key, bytes);
        unawaited(_writeToDisk(c, bytes));
        return bytes;
      }
      return _placeholder();
    } on SocketException {
      return _placeholder();
    } on http.ClientException {
      return _placeholder();
    } catch (_) {
      return _placeholder();
    } finally {
      _releaseSlot();
    }
  }

  Future<void> _acquireSlot() async {
    if (_activeDownloads < _maxConcurrent) {
      _activeDownloads++;
      return;
    }
    final Completer<void> c = Completer<void>();
    _waitingSlots.add(c);
    await c.future;
    _activeDownloads++;
  }

  void _releaseSlot() {
    _activeDownloads--;
    if (_waitingSlots.isNotEmpty) {
      final Completer<void> c = _waitingSlots.removeAt(0);
      c.complete();
    }
  }

  void _rememberInMemory(String key, Uint8List bytes) {
    _memoryCache.remove(key);
    _memoryCache[key] = bytes;
    while (_memoryCache.length > _memoryCacheSize) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  Future<Directory> _ensureCacheDir() {
    final Future<Directory>? existing = _cacheDirFuture;
    if (existing != null) return existing;
    final Future<Directory> future = (() async {
      final Directory base = await getTemporaryDirectory();
      final Directory dir = Directory(p.join(base.path, 'rider_osm_interim'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    })();
    _cacheDirFuture = future;
    return future;
  }

  Future<void> _writeToDisk(TileCoordinates c, Uint8List bytes) async {
    try {
      final Directory dir = await _ensureCacheDir();
      final File f = File(p.join(dir.path, '${c.z}_${c.x}_${c.y}.png'));
      await f.writeAsBytes(bytes, flush: false);
      unawaited(_evictIfOverBudget(dir));
    } catch (_) {
      // Disk write failures are non-fatal; the bytes are still served
      // from the memory cache for the rest of the session.
    }
  }

  Future<void> _evictIfOverBudget(Directory dir) async {
    try {
      final List<File> files = <File>[];
      int total = 0;
      await for (final FileSystemEntity ent in dir.list()) {
        if (ent is File) {
          final FileStat st = await ent.stat();
          total += st.size;
          files.add(ent);
        }
      }
      if (total <= _maxBytes) return;

      // Sort by mtime ascending → oldest first.
      final List<MapEntry<File, DateTime>> dated = await Future.wait(
        files.map((File f) async {
          final FileStat st = await f.stat();
          return MapEntry<File, DateTime>(f, st.modified);
        }),
      );
      dated.sort(
        (MapEntry<File, DateTime> a, MapEntry<File, DateTime> b) =>
            a.value.compareTo(b.value),
      );

      for (final MapEntry<File, DateTime> e in dated) {
        if (total <= _maxBytes) break;
        try {
          final FileStat st = await e.key.stat();
          await e.key.delete();
          total -= st.size;
        } catch (_) {
          /* skip */
        }
      }
    } catch (_) {
      /* best effort */
    }
  }

  Future<Uint8List> _placeholder() async {
    final Uint8List? existing = _placeholderBytes;
    if (existing != null) return existing;
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec);
    final Paint paint = Paint()..color = const Color(0xFFE5E5E5);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 256, 256), paint);
    final ui.Image image = await rec.endRecording().toImage(256, 256);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    final Uint8List bytes = data!.buffer.asUint8List();
    _placeholderBytes = bytes;
    return bytes;
  }
}

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage({required this.provider, required this.coordinates});

  final CachedTileProvider provider;
  final TileCoordinates coordinates;

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_CachedTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      debugLabel:
          'CachedTileProvider(${coordinates.z}/${coordinates.x}/${coordinates.y})',
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final Uint8List bytes = await provider.loadTile(coordinates);
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage &&
      other.coordinates == coordinates &&
      identical(other.provider, provider);

  @override
  int get hashCode => Object.hash(coordinates, identityHashCode(provider));
}
