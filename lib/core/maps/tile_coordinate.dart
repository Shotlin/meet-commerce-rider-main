import 'package:flutter/foundation.dart';

/// An immutable Slippy Map tile coordinate (zoom, x, y).
///
/// Validation rules (OSM / Slippy Map):
///   - `0 <= z <= 19`
///   - `0 <= x < 2^z`
///   - `0 <= y < 2^z`
@immutable
class TileCoordinate {
  const TileCoordinate({required this.z, required this.x, required this.y});

  final int z;
  final int x;
  final int y;

  /// Returns the cache key in the form `'z/x/y'`.
  String toCacheKey() => '$z/$x/$y';

  /// Parses a cache key produced by [toCacheKey] back into a [TileCoordinate].
  ///
  /// Throws [FormatException] when:
  /// - The string does not consist of exactly three `/`-separated parts.
  /// - Any part is not a valid integer.
  /// - The resulting `z`, `x`, or `y` values are out of the valid OSM range.
  static TileCoordinate parseCacheKey(String key) {
    final parts = key.split('/');

    if (parts.length != 3) {
      throw FormatException(
        'TileCoordinate cache key must have exactly 3 parts separated by "/", '
        'got ${parts.length}: "$key"',
      );
    }

    final z = _parseInt(parts[0], 'z', key);
    final x = _parseInt(parts[1], 'x', key);
    final y = _parseInt(parts[2], 'y', key);

    if (z < 0 || z > 19) {
      throw FormatException(
        'TileCoordinate z must be in [0, 19], got $z: "$key"',
      );
    }

    final maxIndex = 1 << z; // 2^z
    if (x < 0 || x >= maxIndex) {
      throw FormatException(
        'TileCoordinate x must be in [0, ${maxIndex - 1}] for z=$z, '
        'got $x: "$key"',
      );
    }
    if (y < 0 || y >= maxIndex) {
      throw FormatException(
        'TileCoordinate y must be in [0, ${maxIndex - 1}] for z=$z, '
        'got $y: "$key"',
      );
    }

    return TileCoordinate(z: z, x: x, y: y);
  }

  static int _parseInt(String s, String field, String fullKey) {
    final value = int.tryParse(s);
    if (value == null) {
      throw FormatException(
        'TileCoordinate $field must be an integer, got "$s": "$fullKey"',
      );
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is TileCoordinate && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => 'TileCoordinate(z: $z, x: $x, y: $y)';
}
