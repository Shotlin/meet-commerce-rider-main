// Shared `glados` generators for the rider-app property tests.
//
// Used by:
//   - test/properties/round_trip_property_test.dart       (Property 4)
//   - test/properties/coordinate_invariants_property_test.dart (Property 5)
//
// Design notes
//   * Generators produce *valid* model instances: non-empty required
//     strings, in-range coordinates, money rounded to 2 decimal places.
//   * Money fields use [moneyGen] which draws doubles in
//     `[0, 99999.99]` already rounded to 2 dp so the model's value
//     equality holds after `fromJson(toJson(x))` (the parser also
//     rounds, but pre-rounding makes the property an identity rather
//     than a tolerance check).
//   * Composite models compose via `Generator.bind` and `combineN` so
//     `glados` can shrink each field independently.
//   * For models with more than 10 fields (`RiderStats`,
//     `RiderEarnings`, `DeliveryOrder`) the typed `combineN` arity is
//     exhausted; those generators are built via [ShrinkableCombination]
//     directly, which preserves field-level shrinking.

// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:glados/glados.dart';

import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_history_entry.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/payout.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_earnings.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_stats.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/store_info.dart';

// ---------------------------------------------------------------------------
// Equality helpers
// ---------------------------------------------------------------------------

/// Rounds [v] to 2 decimal places the same way `OrderParser.readMoney`
/// does. Exposed so tests can pre-round source values and assert the
/// model's plain `==` rather than a tolerance comparator.
double round2(double v) => (v * 100).round() / 100;

/// Compares two doubles for equality after rounding to 2 decimal
/// places. Useful when source data isn't already pre-rounded.
bool moneyEq(double a, double b) => (a * 100).round() == (b * 100).round();

// ---------------------------------------------------------------------------
// Primitive generators
// ---------------------------------------------------------------------------

/// Short, stable strings biased toward realistic delivery-domain values.
/// A fixed pool keeps shrinking deterministic and reproducible.
final Generator<String> _shortStringGen = any.choose<String>(const <String>[
  'Rider',
  'Store',
  'Item',
  'Order',
  'Customer',
  'Salt Lake',
  'Park View',
  'Hub-1',
  'GR-1001',
  'foo',
  'a',
]);

/// Identifier generator: short, distinct, non-empty values.
final Generator<String> _idGen = any.choose<String>(const <String>[
  'order-1',
  'order-2',
  'assign-1',
  'assign-2',
  'item-1',
  'item-2',
  'p-1',
  'p-2',
  'h-1',
]);

/// Public money generator: doubles in `[0, 99999.99]` rounded to 2 dp.
///
/// Used by the round-trip property tests so the model's built-in
/// equality holds after `fromJson(toJson(x))`.
final Generator<double> moneyGen = any
    .doubleInRange(0.0, 99999.99)
    .map<double>(round2);

/// Quantity generator: ints in `[0, 100]`.
final Generator<int> _qtyGen = any.intInRange(0, 101);

/// Small positive int generator: durations / counts in `[1, 120]`.
final Generator<int> _smallPositiveIntGen = any.intInRange(1, 120);

/// Latitude generator strictly inside `[-90, 90]`.
final Generator<double> _latGen = any.doubleInRange(-90.0, 90.0);

/// Longitude generator strictly inside `[-180, 180]`.
final Generator<double> _lngGen = any.doubleInRange(-180.0, 180.0);

/// Optional latitude: either null or in range.
final Generator<double?> _latOptGen = _latGen.nullable;

/// Optional longitude: either null or in range.
final Generator<double?> _lngOptGen = _lngGen.nullable;

/// Optional short string.
final Generator<String?> _shortStringOptGen = _shortStringGen.nullable;

/// Generator over the 5 [AssignmentStatus] variants. Unknown wire
/// values throw separately (R19.5) and are not exercised here.
final Generator<AssignmentStatus> _assignmentStatusGen = any
    .choose<AssignmentStatus>(AssignmentStatus.values);

/// Already-uppercase status strings used by [Payout] and
/// [DeliveryHistoryEntry]. The parser uppercases these on read; we
/// generate them already-uppercase so the round-trip is the identity.
final Generator<String> _upperStatusGen = any.choose<String>(const <String>[
  'PENDING',
  'PAID',
  'FAILED',
  'PROCESSING',
  'DELIVERED',
]);

/// ISO-style date string generator.
final Generator<String> _dateStringGen = any.choose<String>(const <String>[
  '2026-05-11',
  '2026-05-12',
  '2026-05-13',
  '2026-05-14',
  '2026-01-01T00:00:00.000Z',
  '2026-06-15T12:30:00.000Z',
]);

/// Optional ISO-style date string.
final Generator<String?> _dateStringOptGen = _dateStringGen.nullable;

/// Optional id (e.g., `assignmentId` on [DeliveryOrder]).
final Generator<String?> _idOptGen = _idGen.nullable;

/// Period generator (matches the four documented earnings periods).
final Generator<String> _periodGen = any.choose<String>(const <String>[
  'today',
  'week',
  'month',
  'all',
]);

// ---------------------------------------------------------------------------
// Composite generators
// ---------------------------------------------------------------------------

/// Generator for [DeliveryAddress]. lat/lng are independently nullable
/// and strictly in WGS-84 range when present, so the constructor's
/// `Coordinate.validateOrNull` invariant always holds.
final Generator<DeliveryAddress> addressGen = any
    .combine6<
      String,
      String,
      String?,
      String?,
      double?,
      double?,
      DeliveryAddress
    >(
      _shortStringGen,
      _shortStringGen,
      _shortStringOptGen,
      _shortStringOptGen,
      _latOptGen,
      _lngOptGen,
      (
        String name,
        String address,
        String? landmark,
        String? phone,
        double? lat,
        double? lng,
      ) => DeliveryAddress(
        name: name,
        address: address,
        landmark: landmark,
        phone: phone,
        lat: lat,
        lng: lng,
      ),
    );

/// Generator for [DeliveryItem]. All money fields are pre-rounded to
/// 2 dp via [moneyGen].
final Generator<DeliveryItem> itemGen = any
    .combine5<String, String, int, double, double, DeliveryItem>(
      _idGen,
      _shortStringGen,
      _qtyGen,
      moneyGen,
      moneyGen,
      (String id, String name, int qty, double unitPrice, double totalPrice) =>
          DeliveryItem(
            id: id,
            name: name,
            quantity: qty,
            unitPrice: unitPrice,
            totalPrice: totalPrice,
          ),
    );

/// Item list generator, bounded to 0..4 items so the test fits inside
/// `glados`'s default time budget.
final Generator<List<DeliveryItem>> _itemsGen = any
    .listWithLengthInRange<DeliveryItem>(0, 5, itemGen);

/// Generator for [StoreInfo]. Coordinates are required (not nullable)
/// and validated by the constructor, so we draw them from the in-range
/// generators.
final Generator<StoreInfo> storeInfoGen = any
    .combine5<String, String, String?, double, double, StoreInfo>(
      _shortStringGen,
      _shortStringGen,
      _shortStringOptGen,
      _latGen,
      _lngGen,
      (String name, String address, String? phone, double lat, double lng) =>
          StoreInfo(
            name: name,
            address: address,
            phone: phone,
            lat: lat,
            lng: lng,
          ),
    );

/// Generator for [Payout]. Status is already uppercase to match the
/// parser's uppercasing on read.
final Generator<Payout> payoutGen = any
    .combine7<
      String,
      double,
      String,
      String?,
      String?,
      String?,
      String?,
      Payout
    >(
      _idGen,
      moneyGen,
      _upperStatusGen,
      _dateStringOptGen,
      _dateStringOptGen,
      _shortStringOptGen,
      _shortStringOptGen,
      (
        String id,
        double amount,
        String status,
        String? createdAt,
        String? processedAt,
        String? referenceId,
        String? method,
      ) => Payout(
        id: id,
        amount: amount,
        status: status,
        createdAt: createdAt,
        processedAt: processedAt,
        referenceId: referenceId,
        method: method,
      ),
    );

/// Generator for [DeliveryHistoryEntry].
final Generator<DeliveryHistoryEntry> historyEntryGen = any
    .combine6<
      String,
      String,
      String,
      double,
      String?,
      String?,
      DeliveryHistoryEntry
    >(
      _idGen,
      _idGen,
      _upperStatusGen,
      moneyGen,
      _dateStringOptGen,
      _shortStringOptGen,
      (
        String id,
        String orderNumber,
        String status,
        double earnings,
        String? completedAt,
        String? customerArea,
      ) => DeliveryHistoryEntry(
        id: id,
        orderNumber: orderNumber,
        status: status,
        earnings: earnings,
        completedAt: completedAt,
        customerArea: customerArea,
      ),
    );

/// Generator for [EarningsBreakdown].
final Generator<EarningsBreakdown> _breakdownGen = any
    .combine4<double, double, double, double, EarningsBreakdown>(
      moneyGen,
      moneyGen,
      moneyGen,
      moneyGen,
      (double a, double b, double c, double d) => EarningsBreakdown(
        baseDeliveryFees: a,
        distanceBonus: b,
        performanceBonus: c,
        tips: d,
      ),
    );

/// Generator for [DailyEarning].
final Generator<DailyEarning> _dailyEarningGen = any
    .combine3<String, double, int, DailyEarning>(
      _dateStringGen,
      moneyGen,
      _qtyGen,
      (String date, double earnings, int deliveries) =>
          DailyEarning(date: date, earnings: earnings, deliveries: deliveries),
    );

/// Daily earnings list, bounded for performance.
final Generator<List<DailyEarning>> _dailyEarningsGen = any
    .listWithLengthInRange<DailyEarning>(0, 4, _dailyEarningGen);

/// Generator for [DailyStats].
final Generator<DailyStats> _dailyStatsGen = any
    .combine3<String, double, int, DailyStats>(
      _dateStringGen,
      moneyGen,
      _qtyGen,
      (String date, double earnings, int deliveries) =>
          DailyStats(date: date, earnings: earnings, deliveries: deliveries),
    );

/// Weekly stats list, bounded for performance.
final Generator<List<DailyStats>> _weeklyStatsGen = any
    .listWithLengthInRange<DailyStats>(0, 4, _dailyStatsGen);

/// Rating generator, in `[0, 5]` rounded to 2 dp.
final Generator<double> _ratingGen = any
    .doubleInRange(0.0, 5.0)
    .map<double>(round2);

/// Acceptance-rate generator, in `[0, 1]` rounded to 2 dp.
final Generator<double> _acceptanceRateGen = any
    .doubleInRange(0.0, 1.0)
    .map<double>(round2);

/// Optional distance generator, `[0, 100]` km, nullable.
final Generator<double?> _distanceOptGen = any
    .doubleInRange(0.0, 100.0)
    .map<double>(round2)
    .nullable;

/// Generator for [RiderEarnings].
///
/// 11 fields exceed the typed `combineN` arity. Built directly from a
/// [ShrinkableCombination] so per-field shrinking still works.
Generator<RiderEarnings> riderEarningsGen = (Random random, int size) {
  final List<Shrinkable<dynamic>> fields = <Shrinkable<dynamic>>[
    _periodGen(random, size), //  0  period
    moneyGen(random, size), //    1  totalEarnings
    _qtyGen(random, size), //     2  deliveriesCount
    moneyGen(random, size), //    3  avgPerDelivery
    _breakdownGen(random, size), //   4  breakdown
    _dailyEarningsGen(random, size), // 5 dailyBreakdown
    moneyGen(random, size), //    6  pendingPayout
    moneyGen(random, size), //    7  alreadyPaid
    moneyGen(random, size), //    8  lastPayoutAmount
    _dateStringOptGen(random, size), // 9 lastPayoutDate
    _ratingGen(random, size), //  10 rating
  ];
  return ShrinkableCombination<RiderEarnings>(
    fields,
    (List<dynamic> v) => RiderEarnings(
      period: v[0] as String,
      totalEarnings: v[1] as double,
      deliveriesCount: v[2] as int,
      avgPerDelivery: v[3] as double,
      breakdown: v[4] as EarningsBreakdown,
      dailyBreakdown: v[5] as List<DailyEarning>,
      pendingPayout: v[6] as double,
      alreadyPaid: v[7] as double,
      lastPayoutAmount: v[8] as double,
      lastPayoutDate: v[9] as String?,
      rating: v[10] as double,
    ),
  );
};

/// Generator for [RiderStats].
///
/// 12 fields. Same `ShrinkableCombination` strategy as
/// [riderEarningsGen].
Generator<RiderStats> riderStatsGen = (Random random, int size) {
  final List<Shrinkable<dynamic>> fields = <Shrinkable<dynamic>>[
    _qtyGen(random, size), //          0  totalAssigned
    _qtyGen(random, size), //          1  totalDelivered
    _qtyGen(random, size), //          2  deliveredToday
    _qtyGen(random, size), //          3  deliveriesToday
    moneyGen(random, size), //         4  totalEarnings
    moneyGen(random, size), //         5  earningsToday
    moneyGen(random, size), //         6  earningsThisWeek
    _weeklyStatsGen(random, size), //  7  weeklyData
    _ratingGen(random, size), //       8  rating
    _qtyGen(random, size), //          9  totalDeliveries
    _acceptanceRateGen(random, size), // 10 acceptanceRate
    _qtyGen(random, size), //          11 dailyTarget
  ];
  return ShrinkableCombination<RiderStats>(
    fields,
    (List<dynamic> v) => RiderStats(
      totalAssigned: v[0] as int,
      totalDelivered: v[1] as int,
      deliveredToday: v[2] as int,
      deliveriesToday: v[3] as int,
      totalEarnings: v[4] as double,
      earningsToday: v[5] as double,
      earningsThisWeek: v[6] as double,
      weeklyData: v[7] as List<DailyStats>,
      rating: v[8] as double,
      totalDeliveries: v[9] as int,
      acceptanceRate: v[10] as double,
      dailyTarget: v[11] as int,
    ),
  );
};

/// Generator for [DeliveryOrder].
///
/// 13 fields — built from a [ShrinkableCombination] so per-field
/// shrinking still works. Address and item generators are reused so a
/// shrunk counter-example reaches a minimal nested form too.
Generator<DeliveryOrder> orderGen = (Random random, int size) {
  final List<Shrinkable<dynamic>> fields = <Shrinkable<dynamic>>[
    _idGen(random, size), //               0  orderId
    _idOptGen(random, size), //            1  assignmentId
    _shortStringGen(random, size), //      2  orderNumber
    _assignmentStatusGen(random, size), // 3  assignmentStatus
    _shortStringOptGen(random, size), //   4  orderStatus
    moneyGen(random, size), //             5  totalAmount
    _shortStringGen(random, size), //      6  paymentMethod
    moneyGen(random, size), //             7  riderEarning
    _distanceOptGen(random, size), //      8  estimatedDistance
    _smallPositiveIntGen(random, size), // 9  estimatedDuration
    addressGen(random, size), //           10 customerAddress
    addressGen(random, size), //           11 storeAddress
    _itemsGen(random, size), //            12 items
  ];
  return ShrinkableCombination<DeliveryOrder>(
    fields,
    (List<dynamic> v) => DeliveryOrder(
      orderId: v[0] as String,
      assignmentId: v[1] as String?,
      orderNumber: v[2] as String,
      assignmentStatus: v[3] as AssignmentStatus,
      orderStatus: v[4] as String?,
      totalAmount: v[5] as double,
      paymentMethod: v[6] as String,
      riderEarning: v[7] as double,
      estimatedDistance: v[8] as double?,
      estimatedDuration: v[9] as int,
      customerAddress: v[10] as DeliveryAddress,
      storeAddress: v[11] as DeliveryAddress,
      items: v[12] as List<DeliveryItem>,
    ),
  );
};
