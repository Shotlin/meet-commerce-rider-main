import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/maps/tile_coordinate.dart';

void main() {
  group('TileCoordinate.toCacheKey', () {
    test('formats z/x/y correctly for z=0', () {
      const tc = TileCoordinate(z: 0, x: 0, y: 0);
      expect(tc.toCacheKey(), equals('0/0/0'));
    });

    test('formats z/x/y correctly for z=1', () {
      const tc = TileCoordinate(z: 1, x: 1, y: 0);
      expect(tc.toCacheKey(), equals('1/1/0'));
    });

    test('formats z/x/y correctly for mid-range zoom', () {
      const tc = TileCoordinate(z: 10, x: 512, y: 341);
      expect(tc.toCacheKey(), equals('10/512/341'));
    });

    test('formats z/x/y correctly for max zoom z=19', () {
      const tc = TileCoordinate(z: 19, x: 262143, y: 174762);
      expect(tc.toCacheKey(), equals('19/262143/174762'));
    });
  });

  group('TileCoordinate.parseCacheKey — round-trip', () {
    void roundTrip(TileCoordinate tc) {
      final parsed = TileCoordinate.parseCacheKey(tc.toCacheKey());
      expect(
        parsed,
        equals(tc),
        reason: 'round-trip failed for ${tc.toCacheKey()}',
      );
    }

    test('round-trip z=0, x=0, y=0', () {
      roundTrip(const TileCoordinate(z: 0, x: 0, y: 0));
    });

    test('round-trip z=1, x=1, y=1', () {
      roundTrip(const TileCoordinate(z: 1, x: 1, y: 1));
    });

    test('round-trip z=10, x=512, y=341', () {
      roundTrip(const TileCoordinate(z: 10, x: 512, y: 341));
    });

    test('round-trip z=14, x=8192, y=5461', () {
      roundTrip(const TileCoordinate(z: 14, x: 8192, y: 5461));
    });

    test('round-trip z=19, x=0, y=0', () {
      roundTrip(const TileCoordinate(z: 19, x: 0, y: 0));
    });

    test('round-trip z=19, max x and y', () {
      // 2^19 = 524288; max index = 524287
      roundTrip(const TileCoordinate(z: 19, x: 524287, y: 524287));
    });
  });

  group('TileCoordinate.parseCacheKey — out-of-range z', () {
    test('rejects z = -1', () {
      expect(
        () => TileCoordinate.parseCacheKey('-1/0/0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects z = 20', () {
      expect(
        () => TileCoordinate.parseCacheKey('20/0/0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects z = 100', () {
      expect(
        () => TileCoordinate.parseCacheKey('100/0/0'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('TileCoordinate.parseCacheKey — out-of-range x', () {
    test('rejects x = -1 at z=5', () {
      expect(
        () => TileCoordinate.parseCacheKey('5/-1/0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects x = 2^z (equal to max) at z=5', () {
      // 2^5 = 32; valid range is [0, 31]
      expect(
        () => TileCoordinate.parseCacheKey('5/32/0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects x = 2^z + 1 at z=10', () {
      // 2^10 = 1024; valid range is [0, 1023]
      expect(
        () => TileCoordinate.parseCacheKey('10/1024/0'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('TileCoordinate.parseCacheKey — out-of-range y', () {
    test('rejects y = -1 at z=5', () {
      expect(
        () => TileCoordinate.parseCacheKey('5/0/-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects y = 2^z at z=5', () {
      // 2^5 = 32; valid range is [0, 31]
      expect(
        () => TileCoordinate.parseCacheKey('5/0/32'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects y = 2^z + 1 at z=10', () {
      // 2^10 = 1024; valid range is [0, 1023]
      expect(
        () => TileCoordinate.parseCacheKey('10/0/1024'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('TileCoordinate.parseCacheKey — malformed strings', () {
    test('rejects empty string', () {
      expect(
        () => TileCoordinate.parseCacheKey(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects only two parts (missing y)', () {
      expect(
        () => TileCoordinate.parseCacheKey('5/10'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects four parts (extra slash)', () {
      expect(
        () => TileCoordinate.parseCacheKey('5/10/20/30'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects leading extra slash', () {
      expect(
        () => TileCoordinate.parseCacheKey('/5/10/20'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects trailing extra slash', () {
      expect(
        () => TileCoordinate.parseCacheKey('5/10/20/'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-integer z component', () {
      expect(
        () => TileCoordinate.parseCacheKey('abc/10/20'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-integer x component', () {
      expect(
        () => TileCoordinate.parseCacheKey('5/ten/20'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-integer y component', () {
      expect(
        () => TileCoordinate.parseCacheKey('5/10/20.5'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects floating-point z component', () {
      expect(
        () => TileCoordinate.parseCacheKey('5.0/10/20'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects string with only slashes', () {
      expect(
        () => TileCoordinate.parseCacheKey('//'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('TileCoordinate equality and hashCode', () {
    test('equal coordinates are equal', () {
      const a = TileCoordinate(z: 10, x: 512, y: 341);
      const b = TileCoordinate(z: 10, x: 512, y: 341);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different z are not equal', () {
      const a = TileCoordinate(z: 10, x: 512, y: 341);
      const b = TileCoordinate(z: 11, x: 512, y: 341);
      expect(a, isNot(equals(b)));
    });

    test('different x are not equal', () {
      const a = TileCoordinate(z: 10, x: 512, y: 341);
      const b = TileCoordinate(z: 10, x: 513, y: 341);
      expect(a, isNot(equals(b)));
    });

    test('different y are not equal', () {
      const a = TileCoordinate(z: 10, x: 512, y: 341);
      const b = TileCoordinate(z: 10, x: 512, y: 342);
      expect(a, isNot(equals(b)));
    });
  });
}
