import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:meet_commerce_rider_main/core/location/rider_location_provider.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/offers_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_repository.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/presentation/delivery_offer_sheet.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_socket_client.dart';

class _MockDeliveryRepository extends Mock implements DeliveryRepository {}

DeliveryOrder _sampleOrder() => DeliveryOrder(
  orderId: 'order-1',
  orderNumber: 'ORD-001',
  assignmentStatus: AssignmentStatus.assigned,
  totalAmount: 540.0,
  paymentMethod: 'COD',
  riderEarning: 65.0,
  estimatedDistance: 2.4,
  estimatedDuration: 18,
  customerAddress: DeliveryAddress(
    name: 'Priya N',
    address: '12 MG Road, Bengaluru',
    landmark: 'Near Coffee Day',
  ),
  storeAddress: DeliveryAddress(
    name: 'FreshCuts Indiranagar',
    address: '100 Feet Rd, Indiranagar',
  ),
  items: const <DeliveryItem>[
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
);

Widget _harness({
  required Widget child,
  required OffersController controller,
  ValueNotifier<GeoPoint?>? riderLocation,
}) {
  return ProviderScope(
    overrides: [
      offersControllerProvider.overrideWith((Ref ref) => controller),
      if (riderLocation != null)
        riderLocationNotifierProvider.overrideWithValue(riderLocation),
    ],
    child: MaterialApp(home: child),
  );
}

/// Opens the offer sheet for [order] and captures the result.
Future<void> _openSheet(
  WidgetTester tester, {
  required OffersController controller,
  required DeliveryOrder order,
  ValueNotifier<GeoPoint?>? riderLocation,
  void Function(OfferSheetResult result)? onResult,
}) async {
  await tester.pumpWidget(
    _harness(
      controller: controller,
      riderLocation: riderLocation,
      child: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final OfferSheetResult result = await showDeliveryOfferSheet(
                  context,
                  order,
                );
                onResult?.call(result);
              },
              child: const Text('open'),
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
    registerFallbackValue(RejectReason.other);
  });

  Future<void> _setPhoneSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
    'tapping Accept calls OffersController.acceptOffer with the order id',
    (WidgetTester tester) async {
      await _setPhoneSize(tester);

      final _MockDeliveryRepository repo = _MockDeliveryRepository();
      final FakeSocketClient socket = FakeSocketClient();
      final OffersController controller = OffersController(
        repository: repo,
        socket: socket,
      );
      final DeliveryOrder order = _sampleOrder();
      controller.upsertOffer(order);

      when(
        () => repo.acceptOrder(order.orderId),
      ).thenAnswer((_) async => <String, dynamic>{});

      OfferSheetResult? result;
      await tester.pumpWidget(
        _harness(
          controller: controller,
          child: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDeliveryOfferSheet(context, order);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Sheet is visible.
      expect(find.text('New delivery'), findsOneWidget);
      expect(find.text('Accept order'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      // Drag the sheet up to its largest snap so the Accept button is
      // within the test viewport.
      await tester.drag(find.text('New delivery'), const Offset(0, -400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept order'));
      await tester.pumpAndSettle();

      verify(() => repo.acceptOrder(order.orderId)).called(1);
      expect(result?.outcome, OfferSheetOutcome.accepted);
    },
  );

  testWidgets(
    'tapping Decline opens reason picker; selecting reason calls reject',
    (WidgetTester tester) async {
      await _setPhoneSize(tester);

      final _MockDeliveryRepository repo = _MockDeliveryRepository();
      final FakeSocketClient socket = FakeSocketClient();
      final OffersController controller = OffersController(
        repository: repo,
        socket: socket,
      );
      final DeliveryOrder order = _sampleOrder();
      controller.upsertOffer(order);

      when(
        () => repo.rejectOrder(order.orderId, RejectReason.tooFar.wire),
      ).thenAnswer((_) async {});

      OfferSheetResult? result;
      await tester.pumpWidget(
        _harness(
          controller: controller,
          child: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDeliveryOfferSheet(context, order);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.drag(find.text('New delivery'), const Offset(0, -400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      // Reason picker visible.
      expect(find.text('Decline this order'), findsOneWidget);
      expect(find.text('Too far'), findsOneWidget);
      expect(find.text('Vehicle issue'), findsOneWidget);
      expect(find.text('Personal reason'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);

      await tester.tap(find.text('Too far'));
      await tester.pumpAndSettle();

      verify(
        () => repo.rejectOrder(order.orderId, RejectReason.tooFar.wire),
      ).called(1);
      expect(result?.outcome, OfferSheetOutcome.declined);
    },
  );

  testWidgets('shows the route timeline with locality-only drop details '
      'and the sticky action row', (WidgetTester tester) async {
    await _setPhoneSize(tester);

    final _MockDeliveryRepository repo = _MockDeliveryRepository();
    final FakeSocketClient socket = FakeSocketClient();
    final OffersController controller = OffersController(
      repository: repo,
      socket: socket,
    );
    final DeliveryOrder order = _sampleOrder();
    controller.upsertOffer(order);

    await _openSheet(tester, controller: controller, order: order);

    // Timeline labels.
    expect(find.text('Your location'), findsOneWidget);
    expect(find.text('FreshCuts Indiranagar'), findsOneWidget);
    // Customer privacy (§8): locality/landmark yes, name no.
    expect(find.text('Near Coffee Day'), findsOneWidget);
    expect(find.textContaining('Priya N'), findsNothing);
    // Metric chips.
    expect(find.text('2.4 km trip'), findsOneWidget);
    expect(find.text('18 min'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Cash on delivery'), findsOneWidget);
    // Sticky action row visible without scrolling.
    expect(tester.getRect(find.text('Accept order')).bottom, lessThan(1200));
  });

  testWidgets('shows the rider-to-pickup distance when a GPS fix and '
      'store coordinates exist', (WidgetTester tester) async {
    await _setPhoneSize(tester);

    final _MockDeliveryRepository repo = _MockDeliveryRepository();
    final FakeSocketClient socket = FakeSocketClient();
    final OffersController controller = OffersController(
      repository: repo,
      socket: socket,
    );
    final DeliveryOrder order = DeliveryOrder(
      orderId: 'order-1',
      orderNumber: 'ORD-001',
      assignmentStatus: AssignmentStatus.assigned,
      totalAmount: 540.0,
      paymentMethod: 'ONLINE',
      riderEarning: 65.0,
      estimatedDistance: 2.4,
      estimatedDuration: 18,
      customerAddress: DeliveryAddress(
        name: 'Priya N',
        address: '12 MG Road, Bengaluru',
      ),
      storeAddress: DeliveryAddress(
        name: 'FreshCuts Indiranagar',
        address: '100 Feet Rd, Indiranagar',
        lat: 12.9719,
        lng: 77.6412,
      ),
      items: const <DeliveryItem>[],
    );
    controller.upsertOffer(order);

    await _openSheet(
      tester,
      controller: controller,
      order: order,
      riderLocation: ValueNotifier<GeoPoint?>(
        const GeoPoint(12.9352, 77.6245), // Koramangala → ~4-5 km
      ),
    );

    expect(find.textContaining('km to pickup'), findsOneWidget);
  });

  testWidgets('auto-closes with the taken message when the offer is '
      'removed in realtime while the sheet is open', (
    WidgetTester tester,
  ) async {
    await _setPhoneSize(tester);

    final _MockDeliveryRepository repo = _MockDeliveryRepository();
    final FakeSocketClient socket = FakeSocketClient();
    final OffersController controller = OffersController(
      repository: repo,
      socket: socket,
    );
    final DeliveryOrder order = _sampleOrder();
    controller.upsertOffer(order);

    OfferSheetResult? result;
    await _openSheet(
      tester,
      controller: controller,
      order: order,
      onResult: (OfferSheetResult r) => result = r,
    );
    expect(find.text('New delivery'), findsOneWidget);

    // Another rider wins the race → the socket controller calls
    // markExpired, which removes the offer and notifies listeners.
    controller.markExpired(order.orderId);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.outcome, OfferSheetOutcome.dismissed);
    expect(result!.message, kOfferTakenMessage);
    expect(find.text('New delivery'), findsNothing);
  });
}
