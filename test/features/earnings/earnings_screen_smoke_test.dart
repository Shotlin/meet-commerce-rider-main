import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_earnings.dart';
import 'package:meet_commerce_rider_main/features/earnings/application/earnings_controller.dart';
import 'package:meet_commerce_rider_main/features/earnings/presentation/earnings_screen.dart';

/// Stub controller used by the smoke test so it doesn't reach the
/// network. Returns a fixed [RiderEarnings] for every period.
class _StubEarningsController extends EarningsController {
  _StubEarningsController({required this.payload}) : super(api: _UnusedApi());

  final RiderEarnings payload;

  @override
  RiderEarnings? dataFor(EarningsPeriod period) => payload;

  @override
  bool isLoading(EarningsPeriod period) => false;

  @override
  String? error(EarningsPeriod period) => null;

  @override
  Future<void> loadPeriod(
    EarningsPeriod period, {
    bool forceRefresh = false,
  }) async {}
}

/// Sentinel API never invoked because [_StubEarningsController]
/// short-circuits everything. The constructor argument is needed only
/// to satisfy the parent class.
class _UnusedApi implements DeliveryApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in smoke test');
}

void main() {
  testWidgets(
    'EarningsScreen renders the period chips and total without crashing',
    (WidgetTester tester) async {
      const RiderEarnings stub = RiderEarnings(
        period: 'today',
        totalEarnings: 1250.50,
        deliveriesCount: 8,
        avgPerDelivery: 156.31,
        breakdown: EarningsBreakdown(
          baseDeliveryFees: 800.00,
          distanceBonus: 250.00,
          performanceBonus: 150.50,
          tips: 50.00,
        ),
        dailyBreakdown: <DailyEarning>[],
        pendingPayout: 1250.50,
        alreadyPaid: 0,
        lastPayoutAmount: 0,
        rating: 4.7,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            earningsControllerProvider.overrideWith(
              (Ref ref) => _StubEarningsController(payload: stub),
            ),
          ],
          child: const MaterialApp(home: EarningsScreen()),
        ),
      );
      // Pump twice: post-frame callback schedules loadPeriod, then the
      // build-after-load completes synchronously because the stub
      // returns immediately.
      await tester.pumpAndSettle();

      expect(find.text('Earnings'), findsOneWidget);
      // Period chips
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      // Total earnings label
      expect(find.text('TOTAL EARNINGS'), findsOneWidget);
      // Breakdown section labels (StatCard uppercases each label)
      expect(find.text('BREAKDOWN'), findsOneWidget);
      expect(find.text('BASE FEES'), findsOneWidget);
      expect(find.text('DISTANCE BONUS'), findsOneWidget);
      expect(find.text('PERFORMANCE'), findsOneWidget);
      expect(find.text('TIPS'), findsOneWidget);
      // Payouts section
      expect(find.text('PAYOUTS'), findsOneWidget);
      expect(find.text('PENDING PAYOUT'), findsOneWidget);
      expect(find.text('LAST PAYOUT'), findsOneWidget);
    },
  );
}
