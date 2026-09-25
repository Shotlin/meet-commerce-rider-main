import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_stats.dart';

/// The exact live stats JSON shape from the backend contract.
const Map<String, dynamic> _liveStatsJson = <String, dynamic>{
  'totalAssigned': 0,
  'totalDelivered': 0,
  'deliveredToday': 0,
  'deliveriesToday': 0,
  'totalEarnings': 0,
  'earningsToday': 0,
  'earningsThisWeek': 0,
  'weeklyData': <Map<String, dynamic>>[
    <String, dynamic>{'date': '2026-05-11', 'earnings': 0, 'deliveries': 0},
    <String, dynamic>{'date': '2026-05-12', 'earnings': 0, 'deliveries': 0},
    <String, dynamic>{'date': '2026-05-13', 'earnings': 0, 'deliveries': 0},
    <String, dynamic>{'date': '2026-05-14', 'earnings': 0, 'deliveries': 0},
    <String, dynamic>{'date': '2026-05-15', 'earnings': 0, 'deliveries': 0},
    <String, dynamic>{'date': '2026-05-16', 'earnings': 0, 'deliveries': 0},
    <String, dynamic>{'date': '2026-05-17', 'earnings': 0, 'deliveries': 0},
  ],
  'rating': 0,
  'totalDeliveries': 0,
  'acceptanceRate': 0,
  'dailyTarget': 12,
};

void main() {
  group('RiderStats.fromJson — live camelCase shape', () {
    test('parses the exact live stats JSON', () {
      final RiderStats stats = RiderStats.fromJson(_liveStatsJson);

      expect(stats.totalAssigned, 0);
      expect(stats.totalDelivered, 0);
      expect(stats.deliveredToday, 0);
      expect(stats.totalEarnings, closeTo(0.0, 0.001));
      expect(stats.earningsToday, closeTo(0.0, 0.001));
      expect(stats.earningsThisWeek, closeTo(0.0, 0.001));
      expect(stats.weeklyData.length, 7);
      expect(stats.rating, closeTo(0.0, 0.001));
      expect(stats.totalDeliveries, 0);
      expect(stats.acceptanceRate, closeTo(0.0, 0.001));
      expect(stats.dailyTarget, 12);
    });

    test('parses weeklyData entries correctly', () {
      final RiderStats stats = RiderStats.fromJson(_liveStatsJson);

      expect(stats.weeklyData.first.date, '2026-05-11');
      expect(stats.weeklyData.first.earnings, closeTo(0.0, 0.001));
      expect(stats.weeklyData.first.deliveries, 0);
      expect(stats.weeklyData.last.date, '2026-05-17');
    });

    test('parses non-zero values correctly', () {
      final RiderStats stats = RiderStats.fromJson(<String, dynamic>{
        'totalAssigned': 50,
        'totalDelivered': 45,
        'deliveredToday': 3,
        'totalEarnings': 4500.75,
        'earningsToday': 300.50,
        'earningsThisWeek': 1200.25,
        'weeklyData': <Map<String, dynamic>>[
          <String, dynamic>{
            'date': '2026-05-17',
            'earnings': 300.50,
            'deliveries': 3,
          },
        ],
        'rating': 4.8,
        'totalDeliveries': 45,
        'acceptanceRate': 0.9,
        'dailyTarget': 12,
      });

      expect(stats.totalAssigned, 50);
      expect(stats.totalDelivered, 45);
      expect(stats.deliveredToday, 3);
      expect(stats.totalEarnings, closeTo(4500.75, 0.001));
      expect(stats.earningsToday, closeTo(300.50, 0.001));
      expect(stats.earningsThisWeek, closeTo(1200.25, 0.001));
      expect(stats.rating, closeTo(4.8, 0.001));
      expect(stats.acceptanceRate, closeTo(0.9, 0.001));
      expect(stats.weeklyData.length, 1);
      expect(stats.weeklyData.first.earnings, closeTo(300.50, 0.001));
      expect(stats.weeklyData.first.deliveries, 3);
    });

    test('accepts deliveriesToday as alias for deliveredToday', () {
      final RiderStats stats = RiderStats.fromJson(<String, dynamic>{
        'totalAssigned': 0,
        'totalDelivered': 0,
        'deliveriesToday': 5,
        'totalEarnings': 0,
        'earningsToday': 0,
        'earningsThisWeek': 0,
        'weeklyData': <dynamic>[],
        'rating': 0,
        'totalDeliveries': 0,
        'acceptanceRate': 0,
        'dailyTarget': 12,
      });

      expect(stats.deliveredToday, 5);
    });

    test('round-trips through toJson/fromJson', () {
      final RiderStats original = RiderStats.fromJson(_liveStatsJson);
      final RiderStats roundTripped = RiderStats.fromJson(original.toJson());

      expect(roundTripped, equals(original));
    });

    test('copyWith replaces only specified fields', () {
      final RiderStats original = RiderStats.fromJson(_liveStatsJson);
      final RiderStats updated = original.copyWith(
        deliveredToday: 5,
        earningsToday: 500.0,
      );

      expect(updated.deliveredToday, 5);
      expect(updated.earningsToday, closeTo(500.0, 0.001));
      expect(updated.totalAssigned, original.totalAssigned);
      expect(updated.dailyTarget, original.dailyTarget);
    });

    test('handles empty weeklyData gracefully', () {
      final RiderStats stats = RiderStats.fromJson(<String, dynamic>{
        'totalAssigned': 0,
        'totalDelivered': 0,
        'deliveredToday': 0,
        'totalEarnings': 0,
        'earningsToday': 0,
        'earningsThisWeek': 0,
        'weeklyData': <dynamic>[],
        'rating': 0,
        'totalDeliveries': 0,
        'acceptanceRate': 0,
        'dailyTarget': 12,
      });

      expect(stats.weeklyData, isEmpty);
    });
  });

  group('WeeklyDataPoint', () {
    test('parses correctly', () {
      final WeeklyDataPoint point = WeeklyDataPoint.fromJson(<String, dynamic>{
        'date': '2026-05-17',
        'earnings': 150.75,
        'deliveries': 3,
      });

      expect(point.date, '2026-05-17');
      expect(point.earnings, closeTo(150.75, 0.001));
      expect(point.deliveries, 3);
    });

    test('round-trips through toJson/fromJson', () {
      final WeeklyDataPoint original = WeeklyDataPoint.fromJson(
        <String, dynamic>{
          'date': '2026-05-17',
          'earnings': 150.75,
          'deliveries': 3,
        },
      );
      final WeeklyDataPoint roundTripped = WeeklyDataPoint.fromJson(
        original.toJson(),
      );

      expect(roundTripped, equals(original));
    });
  });
}
