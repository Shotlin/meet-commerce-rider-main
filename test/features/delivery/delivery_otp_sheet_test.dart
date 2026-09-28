import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/network/api_exception.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_repository.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_outcome.dart';
import 'package:meet_commerce_rider_main/features/delivery/presentation/delivery_otp_sheet.dart';
import 'package:meet_commerce_rider_main/shared/widgets/app_button.dart';

import '../../helpers/fake_delivery_api.dart';

DeliveryOrder _order({double? amountDue}) => DeliveryOrder(
  orderId: 'order-otp-1',
  orderNumber: 'FC-1',
  assignmentStatus: AssignmentStatus.inTransit,
  totalAmount: 500,
  amountDue: amountDue,
  paymentMethod: 'COD',
  riderEarning: 40,
  estimatedDuration: 12,
  customerAddress: DeliveryAddress(
    name: 'Priya',
    address: '12 MG Road',
    lat: 22.58,
    lng: 88.37,
  ),
  storeAddress: DeliveryAddress(
    name: 'FreshCuts Store',
    address: 'Salt Lake',
    lat: 22.57,
    lng: 88.36,
  ),
  items: const <DeliveryItem>[],
);

late BuildContext _host;
late FakeDeliveryApi _api;
late ActiveDeliveryController _controller;

Future<void> _pumpHost(WidgetTester tester) async {
  _api = FakeDeliveryApi();
  _controller = ActiveDeliveryController(repository: DeliveryRepository(_api))
    ..setActiveDelivery(_order());
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        activeDeliveryControllerProvider.overrideWith((Ref ref) => _controller),
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

Future<DeliveryOutcome?> _open(WidgetTester tester) async {
  DeliveryOutcome? outcome;
  unawaited(
    showDeliveryOtpSheet(
      _host,
      _order(),
    ).then((DeliveryOutcome r) => outcome = r),
  );
  await tester.pumpAndSettle();
  return outcome;
}

void main() {
  testWidgets('asks the rider for the customer code and blocks a short entry', (
    WidgetTester tester,
  ) async {
    await _pumpHost(tester);
    await _open(tester);

    expect(find.text('Confirm delivery'), findsWidgets);
    expect(find.textContaining('delivery code'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('deliveryOtpField')), '12');
    await tester.pump();
    // The action stays disabled until all four digits are in.
    Finder confirm = find.widgetWithText(AppButton, 'Confirm delivery');
    expect(tester.widget<AppButton>(confirm).onPressed, isNull);
    expect(_api.markDeliveredCalls, isEmpty);

    // Non-digits are filtered and the code is capped at four digits.
    await tester.enterText(find.byKey(const Key('deliveryOtpField')), '12ab34');
    await tester.pump();
    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('deliveryOtpField')),
    );
    expect(field.controller!.text, '1234');
    confirm = find.widgetWithText(AppButton, 'Confirm delivery');
    expect(tester.widget<AppButton>(confirm).onPressed, isNotNull);
  });

  testWidgets(
    'a correct code delivers with the OTP and dismisses as delivered',
    (WidgetTester tester) async {
      await _pumpHost(tester);
      DeliveryOutcome? outcome;
      unawaited(
        showDeliveryOtpSheet(
          _host,
          _order(),
        ).then((DeliveryOutcome r) => outcome = r),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('deliveryOtpField')), '4821');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Confirm delivery'));
      await tester.pumpAndSettle();

      expect(_api.markDeliveredCalls, hasLength(1));
      expect(_api.markDeliveredCalls.single.otp, '4821');
      expect(_api.markDeliveredCalls.single.demoMode, isNull);
      expect(outcome, isA<DeliveryOutcomeDelivered>());
    },
  );

  testWidgets('a wrong code keeps the sheet open with an inline error', (
    WidgetTester tester,
  ) async {
    await _pumpHost(tester);
    _api.markDeliveredError = const ApiValidationException(
      'OTP did not match. Ask the customer to read it again',
      statusCode: 400,
      backendCode: 'INVALID_OTP',
    );
    DeliveryOutcome? outcome;
    unawaited(
      showDeliveryOtpSheet(
        _host,
        _order(),
      ).then((DeliveryOutcome r) => outcome = r),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('deliveryOtpField')), '0000');
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, 'Confirm delivery'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('deliveryOtpError')), findsOneWidget);
    expect(find.textContaining('did not match'), findsOneWidget);
    expect(outcome, isNull, reason: 'sheet must stay open for a retry');
  });

  testWidgets('resend asks the backend to send a fresh code to the customer', (
    WidgetTester tester,
  ) async {
    await _pumpHost(tester);
    await _open(tester);

    await tester.tap(find.byKey(const Key('deliveryOtpResend')));
    await tester.pumpAndSettle();

    expect(_api.resendOtpCalls, <String>['order-otp-1']);
    expect(find.byKey(const Key('deliveryOtpNotice')), findsOneWidget);
    // The code itself is never shown to the rider.
    expect(find.textContaining(RegExp(r'\b\d{4}\b')), findsNothing);
  });

  test(
    'DeliveryOrder.dueOnDelivery uses the server amount, else the total',
    () {
      expect(_order(amountDue: 300).dueOnDelivery, 300);
      expect(_order(amountDue: 0).dueOnDelivery, 0);
      expect(_order().dueOnDelivery, 500);
      expect(
        DeliveryOrder.fromJson(<String, dynamic>{
          'orderId': 'o1',
          'assignmentStatus': 'IN_TRANSIT',
          'totalAmount': 500,
          'amountDue': 200,
          'paymentMethod': 'COD',
          'riderEarning': 40,
          'estimatedDuration': 10,
          'customerAddress': <String, dynamic>{'name': 'A', 'address': 'B'},
          'storeAddress': <String, dynamic>{'name': 'S', 'address': 'T'},
          'items': <dynamic>[],
        }).dueOnDelivery,
        200,
      );
    },
  );
}
