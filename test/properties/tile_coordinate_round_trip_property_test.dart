// Property 7 — TileCoordinate cache-key round-trip.
//
// For any valid TileCoordinate `tc` with z ∈ [0, 19],
// x ∈ [0, 2^z), y ∈ [0, 2^z):
//
//   TileCoordinate.parseCacheKey(tc.toCacheKey()) == tc
//
// **Validates: Requirements 3.1, 3.6**
//
// Generator strategy:
//   1. Draw z from [0, 19].
//   2. Draw raw integers for x and y, then constrain them to [0, 2^z)
//      via `abs(raw) % (1 << z)` (special-cased for z == 0 where
//      2^z == 1, so x == y == 0 always).
//   3. Construct a TileCoordinate and assert the round-trip identity.
//
// The test runs the default 100 iterations with per-field shrinking
// provided by glados's `Glados3` harness.

import 'package:glados/glados.dart';

import 'package:meet_commerce_rider_main/core/maps/tile_coordinate.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Generator for valid TileCoordinate triples (z, x, y).
  // ---------------------------------------------------------------------------

  /// z ∈ [0, 19]
  final Generator<int> zGen = any.intInRange(0, 20); // upper bound exclusive

  /// Raw int used to derive x or y via modulo — any int is fine.
  final Generator<int> rawIndexGen = any.int;

  // ---------------------------------------------------------------------------
  // Property 7: TileCoordinate round-trip
  // ---------------------------------------------------------------------------

  // Feature: offline-local-map-sdk, Property 7: TileCoordinate round-trip
  Glados3<int, int, int>(zGen, rawIndexGen, rawIndexGen).test(
    'Property 7: parseCacheKey(toCacheKey(tc)) == tc for all valid coordinates',
    (int z, int rawX, int rawY) {
      // Constrain x and y to [0, 2^z).
      // When z == 0, 2^z == 1, so x and y must both be 0.
      final int maxIndex = 1 << z; // 2^z
      final int x = maxIndex == 1 ? 0 : rawX.abs() % maxIndex;
      final int y = maxIndex == 1 ? 0 : rawY.abs() % maxIndex;

      final TileCoordinate tc = TileCoordinate(z: z, x: x, y: y);
      final String key = tc.toCacheKey();
      final TileCoordinate parsed = TileCoordinate.parseCacheKey(key);

      expect(
        parsed,
        equals(tc),
        reason: 'parseCacheKey("$key") should equal $tc',
      );
    },
  );
}
