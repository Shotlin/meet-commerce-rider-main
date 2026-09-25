import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/config/env.dart';
import 'package:meet_commerce_rider_main/core/config/flavor.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_outcome.dart';
import 'package:meet_commerce_rider_main/features/delivery/presentation/demo_complete_sheet.dart';

/// Phase 5 / R16 proof: the demo-complete delivery bypass must be
/// structurally absent from staging and production builds — the sheet
/// never renders and the call short-circuits to
/// [DeliveryOutcomeCancelled].
DeliveryOrder _order() => DeliveryOrder(
  orderId: 'order-demo-gate-1',
  orderNumber: 'ORD-G1',
  assignmentStatus: AssignmentStatus.assigned,
  totalAmount: 250.0,
  paymentMethod: 'ONLINE',
  riderEarning: 40.0,
  estimatedDuration: 20,
  estimatedDistance: 3.5,
  customerAddress: DeliveryAddress(
    name: 'Test Customer',
    address: 'Salt Lake Sector V, Kolkata',
    lat: 22.58,
    lng: 88.37,
  ),
  storeAddress: DeliveryAddress(
    name: 'FreshCuts Store',
    address: 'Salt Lake, Kolkata',
    lat: 22.57,
    lng: 88.36,
  ),
  items: const <DeliveryItem>[],
);

late BuildContext _host;

Future<void> _pumpHost(WidgetTester tester, Env env) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        envProvider.overrideWithValue(env),
        // The sheet body only reads the controller for its busy flag;
        // a bare instance keeps the test off the socket/location graph.
        activeDeliveryControllerProvider.overrideWith(
          (Ref ref) => ActiveDeliveryController(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            _host = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('production builds never render the demo-complete sheet '
      '(R16.3)', (WidgetTester tester) async {
    await _pumpHost(tester, Env.forFlavor(AppFlavor.prod));

    DeliveryOutcome? outcome;
    unawaited(
      showDemoCompleteSheet(
        _host,
        _order(),
        env: Env.forFlavor(AppFlavor.prod),
      ).then((DeliveryOutcome r) => outcome = r),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demo complete'), findsNothing);
    expect(find.text('Complete demo delivery'), findsNothing);
    expect(outcome, isA<DeliveryOutcomeCancelled>());
  });

  testWidgets('staging builds never render the demo-complete sheet', (
    WidgetTester tester,
  ) async {
    await _pumpHost(tester, Env.forFlavor(AppFlavor.staging));

    DeliveryOutcome? outcome;
    unawaited(
      showDemoCompleteSheet(
        _host,
        _order(),
        env: Env.forFlavor(AppFlavor.staging),
      ).then((DeliveryOutcome r) => outcome = r),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete demo delivery'), findsNothing);
    expect(outcome, isA<DeliveryOutcomeCancelled>());
  });

  testWidgets('dev builds still get the sheet (the affordance itself '
      'is intact)', (WidgetTester tester) async {
    final Env devEnv = Env.forFlavor(AppFlavor.dev);
    expect(devEnv.enableDevAffordances, isTrue);
    await _pumpHost(tester, devEnv);

    final Future<DeliveryOutcome> result = showDemoCompleteSheet(
      _host,
      _order(),
      env: devEnv,
    );
    await tester.pumpAndSettle();

    expect(find.text('Demo complete'), findsOneWidget);
    expect(find.text('Complete demo delivery'), findsOneWidget);
    expect(
      find.text('Bypass OTP and proof photo. Available in dev builds only.'),
      findsOneWidget,
    );

    // Dismissing the sheet resolves to Cancelled (no delivery performed).
    Navigator.of(tester.element(find.text('Demo complete'))).pop();
    await tester.pumpAndSettle();
    expect(await result, isA<DeliveryOutcomeCancelled>());
  });
}
