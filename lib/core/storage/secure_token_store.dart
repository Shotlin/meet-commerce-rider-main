import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/app_logger.dart';

/// Secure persistence for the rider's access and refresh JWTs.
///
/// Wraps [FlutterSecureStorage] so the rest of the app reads/writes
/// tokens through a small typed surface and so tests can swap in an
/// in-memory implementation without dragging the platform channel into
/// unit tests.
///
/// Behaviour:
/// - Writes are atomic per key.
/// - Reads are cached in-memory after the first successful read so
///   the auth interceptor doesn't have to round-trip the platform
///   channel on every authenticated request.
/// - [clear] removes both tokens. The session controller calls this on
///   logout and when a refresh attempt fails.
///
/// Failure modes:
/// - On Android, `flutter_secure_storage` very occasionally returns
///   `BAD_DECRYPT` when the device key store has been reset. We detect
///   this on read by catching [PlatformException] (any platform exception
///   from the storage plugin) and treating it as a missing token, which
///   forces the rider through the login flow again.
abstract class SecureTokenStore {
  /// Returns the latest persisted access token, or null if none.
  Future<String?> readAccessToken();

  /// Returns the latest persisted refresh token, or null if none.
  Future<String?> readRefreshToken();

  /// Persists a new access/refresh pair atomically. The refresh token
  /// rotates on every call to `/auth/refresh-token`, so callers should
  /// always pass both values.
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  });

  /// Removes both tokens. Idempotent.
  Future<void> clear();

  /// True when an access token is currently cached in memory. Used by
  /// the bootstrap to short-circuit the platform read on subsequent app
  /// launches in the same process (mostly relevant in tests).
  bool get hasCachedAccessToken;

  /// Returns the in-memory cached access token synchronously, or `null`
  /// if no token has been loaded yet.
  ///
  /// Used by [SocketClient] which needs a synchronous getter for the auth
  /// token at connect time. The token is guaranteed to be populated after
  /// the session restore completes.
  String? get cachedAccessToken;
}

/// Default implementation backed by `flutter_secure_storage`.
class FlutterSecureTokenStore implements SecureTokenStore {
  /// Constructs a token store pointed at [_storage]. Tests can supply a
  /// custom backend; production wires this to the platform default.
  FlutterSecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? _buildDefaultStorage();

  static FlutterSecureStorage _buildDefaultStorage() {
    return const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
  }

  final FlutterSecureStorage _storage;

  static const String _kAccessToken = 'meetcommerce.rider.accessToken';
  static const String _kRefreshToken = 'meetcommerce.rider.refreshToken';

  String? _accessCache;
  String? _refreshCache;

  @override
  bool get hasCachedAccessToken =>
      _accessCache != null && _accessCache!.isNotEmpty;

  @override
  String? get cachedAccessToken => _accessCache;

  @override
  Future<String?> readAccessToken() async {
    if (_accessCache != null) return _accessCache;
    final String? value = await _safeRead(_kAccessToken);
    _accessCache = value;
    return value;
  }

  @override
  Future<String?> readRefreshToken() async {
    if (_refreshCache != null) return _refreshCache;
    final String? value = await _safeRead(_kRefreshToken);
    _refreshCache = value;
    return value;
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    // Wrap both writes in try/catch but DON'T swallow errors silently —
    // we re-throw so the caller knows persistence failed. We still
    // update the in-memory cache because the access token is needed
    // immediately by the next request.
    _accessCache = accessToken;
    _refreshCache = refreshToken;
    try {
      await Future.wait<void>(<Future<void>>[
        _storage.write(key: _kAccessToken, value: accessToken),
        _storage.write(key: _kRefreshToken, value: refreshToken),
      ]);
    } catch (error, stack) {
      AppLogger.error(
        LogTopic.auth,
        'SecureTokenStore.writeTokens failed',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    _accessCache = null;
    _refreshCache = null;
    try {
      await Future.wait<void>(<Future<void>>[
        _storage.delete(key: _kAccessToken),
        _storage.delete(key: _kRefreshToken),
      ]);
    } catch (error, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'SecureTokenStore.clear failed (ignoring)',
        error: error,
        stackTrace: stack,
      );
      // Don't rethrow on clear: logout must always succeed locally so
      // we never trap the rider in a half-authenticated state.
    }
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (error, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'SecureTokenStore.read($key) failed; treating as missing',
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }
}

/// In-memory implementation used by tests and (defensively) by anything
/// that needs to operate without the platform channel.
@visibleForTesting
class InMemoryTokenStore implements SecureTokenStore {
  /// Constructs an empty in-memory token store.
  InMemoryTokenStore({String? accessToken, String? refreshToken})
    : _access = accessToken,
      _refresh = refreshToken;

  String? _access;
  String? _refresh;

  @override
  bool get hasCachedAccessToken => _access != null && _access!.isNotEmpty;

  @override
  String? get cachedAccessToken => _access;

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}
