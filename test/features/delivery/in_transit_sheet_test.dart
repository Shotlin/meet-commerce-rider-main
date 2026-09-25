import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/collected_payment.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/presentation/in_transit_sheet.dart';
import 'package:meet_commerce_rider_main/shared/widgets/app_button.dart';

import '../../helpers/fake_delivery_api.dart';
import '../../helpers/fake_socket_client.dart';

DeliveryOrder _order({
  String? notes,
  String? instructions,
  String paymentMethod = 'COD',
  double totalAmount = 380,
}) {
  return DeliveryOrder(
    orderId: 'order-1',
    orderNumber: 'ORD-1001',
    assignmentStatus: AssignmentStatus.inTransit,
    totalAmount: totalAmount,
    paymentMethod: paymentMethod,
    riderEarning: 52,
    estimatedDuration: 15,
    customerAddress: DeliveryAddress(
      name: 'Priya N',
      address: '12 MG Road',
      landmark: 'Blue Gate',
      phone: '9800000000',
    ),
    storeAddress: DeliveryAddress(
      name: 'FreshCuts Salt Lake',
      address: 'Sector V',
    ),
    items: <DeliveryItem>[
      DeliveryItem(
        id: 'i1',
        name: 'Rice 5kg',
        quantity: 1,
        unitPrice: 450,
        totalPrice: 450,
      ),
      DeliveryItem(
        id: 'i2',
        name: 'Dal',
        quantity: 2,
        unitPrice: 45,
        totalPrice: 90,
      ),
    ],
    deliveryNotes: notes,
    deliveryInstructions: instructions,
  );
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required DeliveryOrder order,
  ActiveDeliveryController? controller,
}) async {
  final ActiveDeliveryController active =
      controller ?? ActiveDeliveryController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        activeDeliveryControllerProvider.overrideWith((Ref ref) => active),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: InTransitSheet(order: order)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the drop card, call/navigate, and Deliver for a '
      'prepaid order without a COD chip', (WidgetTester tester) async {
    await _pumpSheet(tester, order: _order(paymentMethod: 'ONLINE'));

    expect(find.text('Priya N'), findsOneWidget);
    expect(find.text('Call customer'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    expect(find.text('Deliver'), findsOneWidget);
    expect(find.textContaining('Collect'), findsNothing);
  });

  testWidgets('shows the exact COD amount due while uncollected, and '
      'hides it once the split is recorded', (WidgetTester tester) async {
    final ActiveDeliveryController controller = ActiveDeliveryController()
      ..setActiveDelivery(_order());
    await _pumpSheet(tester, order: _order(), controller: controller);

    expect(
      find.text('Collect ₹380 on delivery'),
      findsOneWidget,
      reason: 'the §13 COD amount-due chip shows the exact customer amount',
    );

    controller.recordCollectedPayment(
      'order-1',
      const CollectedPayment(cashCollected: 380, upiCollected: 0),
    );
    await tester.pump();

    expect(find.text('Collect ₹380 on delivery'), findsNothing);
    expect(find.text('Payment collected · Edit'), findsOneWidget);
  });

  testWidgets('surfaces the customer delivery notes when present', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(
      tester,
      order: _order(notes: 'Leave at the door', instructions: 'Ring twice'),
    );

    expect(find.text('Leave at the door · Ring twice'), findsOneWidget);
  });

  testWidgets('shows no notes strip when the order carries none', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, order: _order());

    expect(find.byIcon(Icons.sticky_note_2_outlined), findsNothing);
  });

  testWidgets('Deliver is disabled for COD until the collection is '
      'recorded, enabled after', (WidgetTester tester) async {
    final ActiveDeliveryController controller = ActiveDeliveryController()
      ..setActiveDelivery(_order());
    await _pumpSheet(tester, order: _order(), controller: controller);

    final Finder deliver = find.ancestor(
      of: find.text('Deliver'),
      matching: find.byType(AppButton),
    );
    AppButton button = tester.widget<AppButton>(deliver);
    expect(button.onPressed, isNull, reason: 'COD blocks delivery');

    controller.recordCollectedPayment(
      'order-1',
      const CollectedPayment(cashCollected: 0, upiCollected: 380),
    );
    await tester.pump();

    button = tester.widget<AppButton>(deliver);
    expect(button.onPressed, isNotNull);
  });

  testWidgets('opens the delivery details sheet with items and notes', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, order: _order(notes: 'Leave at the door'));

    await tester.tap(find.text('Delivery details'));
    await tester.pumpAndSettle();

    expect(find.text('Order #ORD-1001'), findsOneWidget);
    // 'Drop' legitimately appears on both the underlying delivery card
    // and the details sheet opened on top of it.
    expect(find.text('Drop'), findsNWidgets(2));
    expect(find.text('Delivery notes'), findsOneWidget);
    // The note shows on the card strip AND inside the details sheet.
    expect(find.text('Leave at the door'), findsNWidgets(2));
    expect(find.text('1 ×'), findsOneWidget);
    expect(find.text('Rice 5kg'), findsOneWidget);
    expect(find.text('2 ×'), findsOneWidget);
    expect(find.text('Dal'), findsOneWidget);
  });
}
