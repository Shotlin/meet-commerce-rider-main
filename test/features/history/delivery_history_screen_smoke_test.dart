import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_history_entry.dart';
import 'package:meet_commerce_rider_main/features/history/application/history_controller.dart';
import 'package:meet_commerce_rider_main/features/history/presentation/delivery_history_screen.dart';

/// Stub controller that returns a fixed list without touching the
/// network.
class _StubHistoryController extends HistoryController {
  _StubHistoryController({
    required List<DeliveryHistoryEntry> initial,
    required this.totalRows,
  }) : super(api: _UnusedApi()) {
    orders = initial;
    total = totalRows;
    hasMore = false;
  }

  final int totalRows;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadMore() async {}
}

class _UnusedApi implements DeliveryApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in smoke test');
}

void main() {
  testWidgets('DeliveryHistoryScreen renders typed history rows', (
    WidgetTester tester,
  ) async {
    final List<DeliveryHistoryEntry> rows = <DeliveryHistoryEntry>[
      const DeliveryHistoryEntry(
        id: 'order-12345678',
        orderNumber: 'GR-1001',
        status: 'DELIVERED',
        earnings: 89.50,
        completedAt: '2026-05-14T10:00:00.000Z',
        customerArea: 'Salt Lake',
      ),
      const DeliveryHistoryEntry(
        id: 'order-22222222',
        orderNumber: 'GR-1002',
        status: 'CANCELLED',
        earnings: 0,
        completedAt: '2026-05-13T10:00:00.000Z',
        customerArea: 'Park Street',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          historyControllerProvider.overrideWith(
            (Ref ref) =>
                _StubHistoryController(initial: rows, totalRows: rows.length),
          ),
        ],
        child: const MaterialApp(home: DeliveryHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delivery history'), findsOneWidget);
    expect(find.text('#GR-1001'), findsOneWidget);
    expect(find.text('#GR-1002'), findsOneWidget);
    expect(find.text('Salt Lake'), findsOneWidget);
    expect(find.text('Park Street'), findsOneWidget);
    // StatusChip renders status uppercase.
    expect(find.text('DELIVERED'), findsOneWidget);
    expect(find.text('CANCELLED'), findsOneWidget);
  });

  testWidgets('DeliveryHistoryScreen renders the empty state when no orders', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          historyControllerProvider.overrideWith(
            (Ref ref) => _StubHistoryController(
              initial: const <DeliveryHistoryEntry>[],
              totalRows: 0,
            ),
          ),
        ],
        child: const MaterialApp(home: DeliveryHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No deliveries yet'), findsOneWidget);
  });
}
