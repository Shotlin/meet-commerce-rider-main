import 'package:flutter/foundation.dart';

import '../data/order_parser.dart';

/// A single day's data point in the weekly earnings chart returned
/// inside `/delivery/stats.weeklyData`.
@immutable
class DailyStats {
  /// Constructs a daily-stats data point.
  const DailyStats({
    required this.date,
    required this.earnings,
    required this.deliveries,
  });

  /// Parses from the live stats JSON shape.
  factory DailyStats.fromJson(Map<String, dynamic> j) {
    return DailyStats(
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

  /// ISO date string (e.g. `2026-05-11`).
  final String date;

  /// Earnings for this day.
  final double earnings;

  /// Number of deliveries completed on this day.
  final int deliveries;

  @override
  bool operator ==(Object other) {
    return other is DailyStats &&
        other.date == date &&
        other.earnings == earnings &&
        other.deliveries == deliveries;
  }

  @override
  int get hashCode => Object.hash(date, earnings, deliveries);
}

/// Backwards-compatible alias for [DailyStats].
///
/// Older code refers to weekly chart points as `WeeklyDataPoint`; we
/// keep the type name aliased so existing callers continue to compile.
typedef WeeklyDataPoint = DailyStats;

/// Rider performance statistics returned by `GET /delivery/stats`.
///
/// The live backend returns camelCase with numbers as numbers for this
/// route. The parser is still lenient for robustness.
@immutable
class RiderStats {
  /// Constructs rider stats explicitly.
  const RiderStats({
    required this.totalAssigned,
    required this.totalDelivered,
    required this.deliveredToday,
    required this.deliveriesToday,
    required this.totalEarnings,
    required this.earningsToday,
    required this.earningsThisWeek,
    required this.weeklyData,
    required this.rating,
    required this.totalDeliveries,
    required this.acceptanceRate,
    required this.dailyTarget,
  });

  /// Parses the live `/delivery/stats` response shape.
  factory RiderStats.fromJson(Map<String, dynamic> j) {
    final List<DailyStats> weeklyData = OrderParser.readMapList(
      j,
      'weeklyData',
      'weekly_data',
    ).map<DailyStats>(DailyStats.fromJson).toList(growable: false);

    // The live backend exposes both `deliveredToday` and `deliveriesToday`
    // (they are always equal). Read them independently so callers that
    // want the canonical name still get the right answer when only one
    // is present.
    final int? rawDeliveredToday = OrderParser.readIntOpt(
      j,
      'deliveredToday',
      'delivered_today',
    );
    final int? rawDeliveriesToday = OrderParser.readIntOpt(
      j,
      'deliveriesToday',
      'deliveries_today',
    );

    final int deliveredToday = rawDeliveredToday ?? rawDeliveriesToday ?? 0;
    final int deliveriesToday = rawDeliveriesToday ?? rawDeliveredToday ?? 0;

    return RiderStats(
      totalAssigned: OrderParser.readInt(j, 'totalAssigned', 'total_assigned'),
      totalDelivered: OrderParser.readInt(
        j,
        'totalDelivered',
        'total_delivered',
      ),
      deliveredToday: deliveredToday,
      deliveriesToday: deliveriesToday,
      totalEarnings: OrderParser.readDouble(
        j,
        'totalEarnings',
        'total_earnings',
      ),
      earningsToday: OrderParser.readDouble(
        j,
        'earningsToday',
        'earnings_today',
      ),
      earningsThisWeek: OrderParser.readDouble(
        j,
        'earningsThisWeek',
        'earnings_this_week',
      ),
      weeklyData: weeklyData,
      rating: OrderParser.readDouble(j, 'rating'),
      totalDeliveries: OrderParser.readInt(
        j,
        'totalDeliveries',
        'total_deliveries',
      ),
      acceptanceRate: OrderParser.readDouble(
        j,
        'acceptanceRate',
        'acceptance_rate',
      ),
      dailyTarget: OrderParser.readInt(j, 'dailyTarget', 'daily_target'),
    );
  }

  /// Serialises to camelCase JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'totalAssigned': totalAssigned,
    'totalDelivered': totalDelivered,
    'deliveredToday': deliveredToday,
    'deliveriesToday': deliveriesToday,
    'totalEarnings': totalEarnings,
    'earningsToday': earningsToday,
    'earningsThisWeek': earningsThisWeek,
    'weeklyData': weeklyData.map((DailyStats p) => p.toJson()).toList(),
    'rating': rating,
    'totalDeliveries': totalDeliveries,
    'acceptanceRate': acceptanceRate,
    'dailyTarget': dailyTarget,
  };

  /// Returns a copy with the supplied fields replaced.
  RiderStats copyWith({
    int? totalAssigned,
    int? totalDelivered,
    int? deliveredToday,
    int? deliveriesToday,
    double? totalEarnings,
    double? earningsToday,
    double? earningsThisWeek,
    List<DailyStats>? weeklyData,
    double? rating,
    int? totalDeliveries,
    double? acceptanceRate,
    int? dailyTarget,
  }) {
    return RiderStats(
      totalAssigned: totalAssigned ?? this.totalAssigned,
      totalDelivered: totalDelivered ?? this.totalDelivered,
      deliveredToday: deliveredToday ?? this.deliveredToday,
      deliveriesToday: deliveriesToday ?? this.deliveriesToday,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      earningsToday: earningsToday ?? this.earningsToday,
      earningsThisWeek: earningsThisWeek ?? this.earningsThisWeek,
      weeklyData: weeklyData ?? this.weeklyData,
      rating: rating ?? this.rating,
      totalDeliveries: totalDeliveries ?? this.totalDeliveries,
      acceptanceRate: acceptanceRate ?? this.acceptanceRate,
      dailyTarget: dailyTarget ?? this.dailyTarget,
    );
  }

  /// Total orders assigned to this rider (all time).
  final int totalAssigned;

  /// Total orders delivered (all time).
  final int totalDelivered;

  /// Orders delivered today (canonical field name).
  final int deliveredToday;

  /// Same value as [deliveredToday], echoed by the live backend under
  /// the alias `deliveriesToday`. Preserved separately so round-trip
  /// serialisation matches the exact shape the backend returns.
  final int deliveriesToday;

  /// Total earnings (all time).
  final double totalEarnings;

  /// Earnings today.
  final double earningsToday;

  /// Earnings this week.
  final double earningsThisWeek;

  /// Per-day data for the last 7 days.
  final List<DailyStats> weeklyData;

  /// Rider rating (0.0–5.0).
  final double rating;

  /// Total deliveries (may differ from [totalDelivered] depending on
  /// backend counting logic).
  final int totalDeliveries;

  /// Acceptance rate as a fraction (0.0–1.0) or percentage (0–100)
  /// depending on backend formatting.
  final double acceptanceRate;

  /// Daily delivery target set by the platform.
  final int dailyTarget;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RiderStats) return false;
    return other.totalAssigned == totalAssigned &&
        other.totalDelivered == totalDelivered &&
        other.deliveredToday == deliveredToday &&
        other.deliveriesToday == deliveriesToday &&
        other.totalEarnings == totalEarnings &&
        other.earningsToday == earningsToday &&
        other.earningsThisWeek == earningsThisWeek &&
        other.rating == rating &&
        other.totalDeliveries == totalDeliveries &&
        other.acceptanceRate == acceptanceRate &&
        other.dailyTarget == dailyTarget &&
        _listEquals(other.weeklyData, weeklyData);
  }

  @override
  int get hashCode => Object.hash(
    totalAssigned,
    totalDelivered,
    deliveredToday,
    deliveriesToday,
    totalEarnings,
    earningsToday,
    earningsThisWeek,
    Object.hashAll(weeklyData),
    rating,
    totalDeliveries,
    acceptanceRate,
    dailyTarget,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
