import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/network/api_envelope.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/payout.dart';
import 'package:meet_commerce_rider_main/features/earnings/presentation/payout_history_screen.dart';

/// Stub [DeliveryApi] that returns a single page of payouts. Other
/// methods throw if called, which keeps the test honest about what the
/// screen actually exercises.
class _StubDeliveryApi implements DeliveryApi {
  _StubDeliveryApi(this._items);

  final List<Payout> _items;

  @override
  Future<({List<Payout> items, Pagination pagination})> getPayouts({
    int page = 1,
    int limit = 20,
  }) async {
    return (
      items: _items,
      pagination: Pagination(page: 1, totalPages: 1, total: _items.length),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in smoke test');
}

void main() {
  testWidgets('PayoutHistoryScreen renders typed payout rows', (
    WidgetTester tester,
  ) async {
    final List<Payout> rows = <Payout>[
      const Payout(
        id: 'pay-abcdef1234',
        amount: 1500,
        status: 'PAID',
        createdAt: '2026-05-10T08:00:00.000Z',
      ),
      const Payout(
        id: 'pay-pending5678',
        amount: 720.5,
        status: 'PENDING',
        createdAt: '2026-05-12T08:00:00.000Z',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          deliveryApiProvider.overrideWithValue(_StubDeliveryApi(rows)),
        ],
        child: const MaterialApp(home: PayoutHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payout history'), findsOneWidget);
    // Truncated 8-char id with leading hash.
    expect(find.text('#PAY-ABCD'), findsOneWidget);
    expect(find.text('#PAY-PEND'), findsOneWidget);
    // Status chips uppercase.
    expect(find.text('PAID'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
  });

  testWidgets('PayoutHistoryScreen shows empty state with no payouts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          deliveryApiProvider.overrideWithValue(
            _StubDeliveryApi(const <Payout>[]),
          ),
        ],
        child: const MaterialApp(home: PayoutHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No payouts yet'), findsOneWidget);
  });
}
