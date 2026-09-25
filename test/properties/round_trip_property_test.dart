// Property 4 — JSON round-trip parsing.
//
// For any valid instance `x` of a backend-facing model
// (DeliveryOrder, DeliveryAddress, DeliveryItem, RiderStats,
// RiderEarnings, StoreInfo, Payout, DeliveryHistoryEntry), the model
// produced by `Model.fromJson(x.toJson())` is semantically equal to `x`
// under the model's value equality, where monetary fields are
// compared after rounding to two decimal places.
//
// Validates: Requirements 19.3, 28.2, 28.4.
//
// Each `Glados<X>(...)` test runs the default 100 iterations with
// per-field shrinking via `combineN` / `ShrinkableCombination` from the
// shared generators in `_generators.dart`. Money fields are
// pre-rounded to 2 dp so the model's `==` matches without a tolerance
// comparator.

import 'package:glados/glados.dart';

import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_history_entry.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/payout.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_earnings.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_stats.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/store_info.dart';

import '_generators.dart';

void main() {
  group('Property 4: parse(serialize(x)) ≡ x', () {
    // Feature: freashcut-rider, Property 4: parse(serialize(x)) ≡ x for DeliveryAddress
    Glados<DeliveryAddress>(addressGen).test('DeliveryAddress round-trips', (
      DeliveryAddress x,
    ) {
      final Map<String, dynamic> json = x.toJson();
      final DeliveryAddress y = DeliveryAddress.fromJson(json);
      expect(y, x);
    });

    // Feature: freashcut-rider, Property 4: parse(serialize(x)) ≡ x for DeliveryItem
    Glados<DeliveryItem>(itemGen).test('DeliveryItem round-trips', (
      DeliveryItem x,
    ) {
      final Map<String, dynamic> json = x.toJson();
      final DeliveryItem y = DeliveryItem.fromJson(json);
      expect(y, x);
    });

    // Feature: freashcut-rider, Property 4: parse(serialize(x)) ≡ x for StoreInfo
    Glados<StoreInfo>(storeInfoGen).test('StoreInfo round-trips', (
      StoreInfo x,
    ) {
      final Map<String, dynamic> json = x.toJson();
      final StoreInfo y = StoreInfo.fromJson(json);
      expect(y, x);
    });

    // Feature: freashcut-rider, Property 4: parse(serialize(x)) ≡ x for Payout
    Glados<Payout>(payoutGen).test('Payout round-trips', (Payout x) {
      final Map<String, dynamic> json = x.toJson();
      final Payout y = Payout.fromJson(json);
      expect(y, x);
    });

    // Feature: freashcut-rider, Property 4: parse(serialize(x)) ≡ x for DeliveryHistoryEntry
    Glados<DeliveryHistoryEntry>(historyEntryGen).test(
      'DeliveryHistoryEntry round-trips',
      (DeliveryHistoryEntry x) {
        final Map<String, dynamic> json = x.toJson();
        final DeliveryHistoryEntry y = DeliveryHistoryEntry.fromJson(json);
        expect(y, x);
      },
    );

    // Feature: freashcut-rider, Property 4: parse(serialize(x)) ≡ x for RiderStats
    Glados<RiderStats>(riderStatsGen).test('RiderStats round-trips', (
      RiderStats x,
    ) {
      final Map<String, dynamic> json = x.toJson();
      final RiderStats y = RiderStats.fromJson(json);
      expect(y, x);
    });

    // Feature: freashcut-rider, Property 4: parse(serialize(x)) ≡ x for RiderEarnings
    Glados<RiderEarnings>(riderEarningsGen).test('RiderEarnings round-trips', (
      RiderEarnings x,
    ) {
      final Map<String, dynamic> json = x.toJson();
      final RiderEarnings y = RiderEarnings.fromJson(json);
      expect(y, x);
    });

    // Feature: freashcut-rider, Property 4: parse(serialize(x)) ≡ x for DeliveryOrder
    Glados<DeliveryOrder>(orderGen).test('DeliveryOrder round-trips', (
      DeliveryOrder x,
    ) {
      final Map<String, dynamic> json = x.toJson();
      final DeliveryOrder y = DeliveryOrder.fromJson(json);
      expect(y, x);
    });
  });

  // moneyEq is exposed by `_generators.dart` for callers that want to
  // assert money equivalence without pre-rounding source data; the
  // round-trip suite above does pre-round so plain `==` suffices.
  group('moneyEq helper', () {
    test('returns true for values equal at 2dp', () {
      expect(moneyEq(10.005, 10.01), isTrue);
      expect(moneyEq(10.0, 10.0), isTrue);
      expect(moneyEq(10.999, 11.0), isTrue);
    });

    test('returns false for values differing at 2dp', () {
      expect(moneyEq(10.0, 10.01), isFalse);
      expect(moneyEq(10.005, 10.02), isFalse);
    });
  });
}
