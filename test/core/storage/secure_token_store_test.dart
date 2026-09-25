import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/storage/secure_token_store.dart';

/// Unit tests for [SecureTokenStore], exercising the in-memory test
/// double. The platform-backed implementation is identical aside from
/// the storage source, and is covered indirectly by widget integration
/// tests once the auth flow lands.
void main() {
  group('InMemoryTokenStore', () {
    test('starts empty when constructed without args', () async {
      final SecureTokenStore store = InMemoryTokenStore();
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(store.hasCachedAccessToken, isFalse);
    });

    test('writeTokens persists both values', () async {
      final SecureTokenStore store = InMemoryTokenStore();
      await store.writeTokens(accessToken: 'a', refreshToken: 'r');
      expect(await store.readAccessToken(), 'a');
      expect(await store.readRefreshToken(), 'r');
      expect(store.hasCachedAccessToken, isTrue);
    });

    test('clear removes both values', () async {
      final SecureTokenStore store = InMemoryTokenStore(
        accessToken: 'a',
        refreshToken: 'r',
      );
      expect(store.hasCachedAccessToken, isTrue);
      await store.clear();
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(store.hasCachedAccessToken, isFalse);
    });

    test('writeTokens overwrites prior values', () async {
      final SecureTokenStore store = InMemoryTokenStore(
        accessToken: 'old',
        refreshToken: 'oldR',
      );
      await store.writeTokens(accessToken: 'new', refreshToken: 'newR');
      expect(await store.readAccessToken(), 'new');
      expect(await store.readRefreshToken(), 'newR');
    });

    test('hasCachedAccessToken returns false for an empty string', () {
      final SecureTokenStore store = InMemoryTokenStore(accessToken: '');
      expect(store.hasCachedAccessToken, isFalse);
    });
  });
}
