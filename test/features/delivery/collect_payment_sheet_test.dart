import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/network/api_exception.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_repository.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/presentation/collect_payment_sheet.dart';
import 'package:meet_commerce_rider_main/shared/widgets/app_text_field.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_delivery_api.dart';

class _MockDeliveryRepository extends Mock implements DeliveryRepository {}

DeliveryOrder _order() => DeliveryOrder(
  orderId: 'order-1',
  orderNumber: 'ORD-1001',
  assignmentStatus: AssignmentStatus.inTransit,
  totalAmount: 380,
  paymentMethod: 'COD',
  riderEarning: 52,
  estimatedDuration: 15,
  customerAddress: DeliveryAddress(name: 'Priya N', address: '12 MG Road'),
  storeAddress: DeliveryAddress(name: 'FreshCuts', address: 'Sector V'),
  items: <DeliveryItem>[],
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  required DeliveryRepository repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[deliveryRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Builder(
              builder: (BuildContext context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await showCollectPaymentSheet(context, _order());
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(const <String, dynamic>{});
  });

  testWidgets('posting a balanced split persists it server-side with the '
      'deterministic idempotency key and closes the sheet', (
    WidgetTester tester,
  ) async {
    final FakeDeliveryApi api = FakeDeliveryApi();
    final DeliveryRepository repo = DeliveryRepository(api);
    await _pumpSheet(tester, repo: repo);

    await tester.enterText(
      find.widgetWithText(AppTextField, 'Cash collected').first,
      '380',
    );
    await tester.enterText(
      find.widgetWithText(AppTextField, 'UPI collected').first,
      '0',
    );
    await tester.pump();

    await tester.tap(find.text('Confirm & continue'));
    await tester.pumpAndSettle();

    // The sheet closed on success.
    expect(find.text('Confirm & continue'), findsNothing);
    expect(api.postCollectionCalls, hasLength(1));
    final (String orderId, double cash, double upi, String key) =
        api.postCollectionCalls.single;
    expect(orderId, 'order-1');
    expect(cash, 380);
    expect(upi, 0);
    // Deterministic, retry-safe key — no new dependency, replay-safe.
    expect(key, 'collection-order-1');
  });

  testWidgets('an amount mismatch from the backend keeps the rider on '
      'the sheet with the message (§14: remain on collection screen)', (
    WidgetTester tester,
  ) async {
    // Locally balanced (380/0 matches the order total) but the backend
    // rejects the post — the rider must stay on the sheet with the
    // backend's message (§14: remain on collection screen).
    final FakeDeliveryApi api = FakeDeliveryApi()
      ..postCollectionError = const ApiValidationException(
        'Collection could not be recorded. Try again',
        statusCode: 400,
        backendCode: 'COLLECTION_AMOUNT_MISMATCH',
      );
    final DeliveryRepository repo = DeliveryRepository(api);
    await _pumpSheet(tester, repo: repo);

    await tester.enterText(
      find.widgetWithText(AppTextField, 'Cash collected').first,
      '380',
    );
    await tester.enterText(
      find.widgetWithText(AppTextField, 'UPI collected').first,
      '0',
    );
    await tester.pump();

    await tester.tap(find.text('Confirm & continue'));
    await tester.pumpAndSettle();

    // Still on the sheet, with the backend's message shown.
    expect(find.text('Confirm & continue'), findsOneWidget);
    expect(
      find.text('Collection could not be recorded. Try again'),
      findsOneWidget,
    );
    // A retry is possible without reopening.
    api.postCollectionError = null;
    await tester.tap(find.text('Confirm & continue'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm & continue'), findsNothing);
    expect(api.postCollectionCalls, hasLength(2));
  });
}
