import 'package:flutter/foundation.dart';

import '../data/order_parser.dart';

/// Breakdown of earnings by category, returned inside
/// `/delivery/earnings.breakdown`.
@immutable
class EarningsBreakdown {
  /// Constructs an earnings breakdown.
  const EarningsBreakdown({
    required this.baseDeliveryFees,
    required this.distanceBonus,
    required this.performanceBonus,
    required this.tips,
  });

  /// Parses from JSON.
  factory EarningsBreakdown.fromJson(Map<String, dynamic> j) {
    return EarningsBreakdown(
      baseDeliveryFees: OrderParser.readDouble(
        j,
        'baseDeliveryFees',
        'base_delivery_fees',
      ),
      distanceBonus: OrderParser.readDouble(
        j,
        'distanceBonus',
        'distance_bonus',
      ),
      performanceBonus: OrderParser.readDouble(
        j,
        'performanceBonus',
        'performance_bonus',
      ),
      tips: OrderParser.readDouble(j, 'tips'),
    );
  }

  /// Serialises to camelCase JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'baseDeliveryFees': baseDeliveryFees,
    'distanceBonus': distanceBonus,
    'performanceBonus': performanceBonus,
    'tips': tips,
  };

  /// Base delivery fees earned.
  final double baseDeliveryFees;

  /// Distance-based bonus.
  final double distanceBonus;

  /// Performance-based bonus.
  final double performanceBonus;

  /// Tips received.
  final double tips;

  @override
  bool operator ==(Object other) {
    return other is EarningsBreakdown &&
        other.baseDeliveryFees == baseDeliveryFees &&
        other.distanceBonus == distanceBonus &&
        other.performanceBonus == performanceBonus &&
        other.tips == tips;
  }

  @override
  int get hashCode =>
      Object.hash(baseDeliveryFees, distanceBonus, performanceBonus, tips);
}

/// A single day's earnings breakdown returned inside
/// `/delivery/earnings.dailyBreakdown`.
@immutable
class DailyEarning {
  /// Constructs a daily earnings entry.
  const DailyEarning({
    required this.date,
    required this.earnings,
    required this.deliveries,
  });

  /// Parses from JSON.
  factory DailyEarning.fromJson(Map<String, dynamic> j) {
    return DailyEarning(
      date: OrderParser.readString(j, 'date'),
      earnings: OrderParser.readDouble(j, 'earnings'),
      deliveries: OrderParser.readInt(j, 'deliveries'),
    );
  }

  /// Serialises to JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'date': date,
    'earnings': earnings,
    'deliveries': deliveries,
  };

  /// ISO date string.
  final String date;

  /// Earnings for this day.
  final double earnings;

  /// Number of deliveries on this day.
  final int deliveries;

  @override
  bool operator ==(Object other) {
    return other is DailyEarning &&
        other.date == date &&
        other.earnings == earnings &&
        other.deliveries == deliveries;
  }

  @override
  int get hashCode => Object.hash(date, earnings, deliveries);
}

/// Backwards-compatible alias for [DailyEarning].
typedef DailyBreakdown = DailyEarning;

/// Rider earnings for a given period, returned by
/// `GET /delivery/earnings?period=...`.
///
/// The live backend returns camelCase with numbers as numbers for this
/// route. The parser is still lenient for robustness.
@immutable
class RiderEarnings {
  /// Constructs rider earnings explicitly.
  const RiderEarnings({
    required this.period,
    required this.totalEarnings,
    required this.deliveriesCount,
    required this.avgPerDelivery,
    required this.breakdown,
    required this.dailyBreakdown,
    required this.pendingPayout,
    required this.alreadyPaid,
    required this.lastPayoutAmount,
    this.lastPayoutDate,
    required this.rating,
  });

  /// Parses the live `/delivery/earnings` response shape.
  factory RiderEarnings.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic>? rawBreakdown = OrderParser.readMap(
      j,
      'breakdown',
    );
    final EarningsBreakdown breakdown = rawBreakdown != null
        ? EarningsBreakdown.fromJson(rawBreakdown)
        : const EarningsBreakdown(
            baseDeliveryFees: 0,
            distanceBonus: 0,
            performanceBonus: 0,
            tips: 0,
          );

    final List<DailyEarning> dailyBreakdown = OrderParser.readMapList(
      j,
      'dailyBreakdown',
      'daily_breakdown',
    ).map<DailyEarning>(DailyEarning.fromJson).toList(growable: false);

    return RiderEarnings(
      period: OrderParser.readString(j, 'period'),
      totalEarnings: OrderParser.readDouble(
        j,
        'totalEarnings',
        'total_earnings',
      ),
      deliveriesCount: OrderParser.readInt(
        j,
        'deliveriesCount',
        'deliveries_count',
      ),
      avgPerDelivery: OrderParser.readDouble(
        j,
        'avgPerDelivery',
        'avg_per_delivery',
      ),
      breakdown: breakdown,
      dailyBreakdown: dailyBreakdown,
      pendingPayout: OrderParser.readDouble(
        j,
        'pendingPayout',
        'pending_payout',
      ),
      alreadyPaid: OrderParser.readDouble(j, 'alreadyPaid', 'already_paid'),
      lastPayoutAmount: OrderParser.readDouble(
        j,
        'lastPayoutAmount',
        'last_payout_amount',
      ),
      lastPayoutDate: OrderParser.readStringOpt(
        j,
        'lastPayoutDate',
        'last_payout_date',
      ),
      rating: OrderParser.readDouble(j, 'rating'),
    );
  }

  /// Serialises to camelCase JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'period': period,
    'totalEarnings': totalEarnings,
    'deliveriesCount': deliveriesCount,
    'avgPerDelivery': avgPerDelivery,
    'breakdown': breakdown.toJson(),
    'dailyBreakdown': dailyBreakdown
        .map((DailyEarning d) => d.toJson())
        .toList(),
    'pendingPayout': pendingPayout,
    'alreadyPaid': alreadyPaid,
    'lastPayoutAmount': lastPayoutAmount,
    'lastPayoutDate': lastPayoutDate,
    'rating': rating,
  };

  /// Returns a copy with the supplied fields replaced.
  RiderEarnings copyWith({
    String? period,
    double? totalEarnings,
    int? deliveriesCount,
    double? avgPerDelivery,
    EarningsBreakdown? breakdown,
    List<DailyEarning>? dailyBreakdown,
    double? pendingPayout,
    double? alreadyPaid,
    double? lastPayoutAmount,
    String? lastPayoutDate,
    double? rating,
  }) {
    return RiderEarnings(
      period: period ?? this.period,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      deliveriesCount: deliveriesCount ?? this.deliveriesCount,
      avgPerDelivery: avgPerDelivery ?? this.avgPerDelivery,
      breakdown: breakdown ?? this.breakdown,
      dailyBreakdown: dailyBreakdown ?? this.dailyBreakdown,
      pendingPayout: pendingPayout ?? this.pendingPayout,
      alreadyPaid: alreadyPaid ?? this.alreadyPaid,
      lastPayoutAmount: lastPayoutAmount ?? this.lastPayoutAmount,
      lastPayoutDate: lastPayoutDate ?? this.lastPayoutDate,
      rating: rating ?? this.rating,
    );
  }

  /// Period identifier (`today`, `week`, `month`, `all`).
  final String period;

  /// Total earnings for the period.
  final double totalEarnings;

  /// Number of deliveries in the period.
  final int deliveriesCount;

  /// Average earnings per delivery.
  final double avgPerDelivery;

  /// Earnings breakdown by category.
  final EarningsBreakdown breakdown;

  /// Per-day breakdown within the period.
  final List<DailyEarning> dailyBreakdown;

  /// Amount pending payout.
  final double pendingPayout;

  /// Amount already paid out.
  final double alreadyPaid;

  /// Amount of the last payout.
  final double lastPayoutAmount;

  /// Date of the last payout. Null when no payout has been made.
  final String? lastPayoutDate;

  /// Rider rating for the period.
  final double rating;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RiderEarnings) return false;
    return other.period == period &&
        other.totalEarnings == totalEarnings &&
        other.deliveriesCount == deliveriesCount &&
        other.avgPerDelivery == avgPerDelivery &&
        other.breakdown == breakdown &&
        other.pendingPayout == pendingPayout &&
        other.alreadyPaid == alreadyPaid &&
        other.lastPayoutAmount == lastPayoutAmount &&
        other.lastPayoutDate == lastPayoutDate &&
        other.rating == rating &&
        _listEquals(other.dailyBreakdown, dailyBreakdown);
  }

  @override
  int get hashCode => Object.hash(
    period,
    totalEarnings,
    deliveriesCount,
    avgPerDelivery,
    breakdown,
    Object.hashAll(dailyBreakdown),
    pendingPayout,
    alreadyPaid,
    lastPayoutAmount,
    lastPayoutDate,
    rating,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
