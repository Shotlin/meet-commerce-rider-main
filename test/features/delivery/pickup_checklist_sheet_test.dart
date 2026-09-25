import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_repository.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/pickup_session.dart';
import 'package:meet_commerce_rider_main/features/delivery/presentation/pickup_checklist_sheet.dart';
import 'package:mocktail/mocktail.dart';

class _MockDeliveryRepository extends Mock implements DeliveryRepository {}

// Mirrors the real-world report: an 8-item grocery order (bottle gourd,
// onion, tomato, coriander, potato, chilli, lady finger, cabbage) whose
// checklist sheet clipped past the "Confirm Pickup" button with no way to
// scroll to it or the trailing items.
PickupVerification _eightItemVerification() => const PickupVerification(
  orderId: 'order-1',
  orderNumber: 'BKLOO-20260818-012',
  customerName: 'Sayan Mondal',
  customerPhone: '9775845587',
  addressLine: 'Home, dhhddh, nsos, hdhd, KOLkata, habra, 743287',
  lat: null,
  lng: null,
  deliveryNotes: null,
  deliveryInstructions: null,
  items: <PickupChecklistItem>[
    PickupChecklistItem(
      name: 'Bottle Gourd (Dudhi)',
      quantity: 1,
      unit: '450 gm',
    ),
    PickupChecklistItem(name: 'Onion(Kanda)', quantity: 1, unit: '250 gm'),
    PickupChecklistItem(name: 'Tomato (Tameta)', quantity: 1, unit: '250 gm'),
    PickupChecklistItem(
      name: 'Coriander (Desi Dhana)',
      quantity: 1,
      unit: '100 gm',
    ),
    PickupChecklistItem(name: 'Potato (Bateta)', quantity: 1, unit: '500 gm'),
    PickupChecklistItem(
      name: 'Long Chilli (Pati marcha)',
      quantity: 1,
      unit: '250 gm',
    ),
    PickupChecklistItem(
      name: 'Lady Finger (Bhindo)',
      quantity: 1,
      unit: '250 gm',
    ),
    PickupChecklistItem(
      name: 'Cabbage (kobi)',
      quantity: 1,
      unit: '600g - 700g',
    ),
  ],
);

void main() {
  Future<void> setPhoneSize(WidgetTester tester) async {
    // Matches a typical Android device (close to the Pixel 9 emulator).
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
    'checklist sheet with 8 items keeps Confirm Pickup on-screen and the item list scrollable',
    (WidgetTester tester) async {
      await setPhoneSize(tester);

      final _MockDeliveryRepository repo = _MockDeliveryRepository();
      final ActiveDeliveryController active = ActiveDeliveryController(
        repository: repo,
      );
      when(() => repo.markPickedUp(any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeDeliveryControllerProvider.overrideWith((Ref ref) => active),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showPickupChecklistSheet(
                      context,
                      'order-1',
                      _eightItemVerification(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // No overflow / layout exception from the 8-item list.
      expect(tester.takeException(), isNull);

      // find.text alone matches anywhere in the tree regardless of scroll
      // clipping — SingleChildScrollView still lays out its whole child, it
      // just clips what's painted — so "reachable" has to be checked with
      // .hitTestable(), which respects clip regions the way a real tap
      // would. The core regression: "Confirm Pickup" must be hit-testable
      // right away, with no scroll of anything required to reach it.
      expect(find.text('Confirm Pickup').hitTestable(), findsOneWidget);

      // The last couple of items must NOT be hit-testable yet — proving
      // the item list is genuinely height-capped and clipping, not just
      // short enough to fit on its own.
      expect(find.text('1 × Lady Finger (Bhindo)').hitTestable(), findsNothing);
      expect(find.text('1 × Cabbage (kobi)').hitTestable(), findsNothing);

      // There must be real, positive scroll extent on the item list —
      // i.e. it's an actual scrollable, not a fixed-height dead end.
      final ScrollableState itemListScroll = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      expect(itemListScroll.position.maxScrollExtent, greaterThan(0));

      // ...and the trailing items become reachable by scrolling the item
      // list itself.
      await tester.drag(
        find.text('1 × Bottle Gourd (Dudhi)'),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1 × Cabbage (kobi)').hitTestable(), findsOneWidget);
      // Confirm Pickup stays reachable throughout — scrolling the item
      // list must not have carried the button off-screen with it.
      expect(find.text('Confirm Pickup').hitTestable(), findsOneWidget);

      // The full flow still works end to end: every switch (whichever ones
      // are currently reachable, scrolling as needed) gets toggled, then
      // Confirm Pickup actually submits.
      final int switchCount = tester.widgetList(find.byType(Switch)).length;
      for (int i = 0; i < switchCount; i++) {
        final Finder toggle = find.byType(Switch).at(i);
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final Finder confirmAgain = find.text('Confirm Pickup');
      await tester.ensureVisible(confirmAgain);
      await tester.pumpAndSettle();
      await tester.tap(confirmAgain);
      await tester.pumpAndSettle();

      verify(() => repo.markPickedUp('order-1')).called(1);
    },
  );

  testWidgets(
    'Confirm Pickup stays reachable even when the customer card alone is tall '
    '(long address + instructions eating into the space a fixed item-list '
    'height budget would have assumed was free)',
    (WidgetTester tester) async {
      // A smaller/older device, deliberately: less headroom overall makes
      // it easier for a tall customer card to push the button off.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final _MockDeliveryRepository repo = _MockDeliveryRepository();
      final ActiveDeliveryController active = ActiveDeliveryController(
        repository: repo,
      );

      const PickupVerification verification = PickupVerification(
        orderId: 'order-2',
        orderNumber: 'BKLOO-20260818-099',
        customerName: 'Sayan Mondal',
        customerPhone: '9775845587',
        addressLine:
            'Home, Flat 12B, Behind Old Water Tank, Near Aspirea School, '
            'Off Main Road, Habra Municipality Ward 9, Kolkata Metropolitan Area, '
            'West Bengal, 743287',
        lat: null,
        lng: null,
        deliveryNotes:
            'Ring the bell twice, dog in the yard, leave with the '
            'security guard if nobody answers within five minutes',
        deliveryInstructions:
            'Call before arriving, gate code is 4521, second '
            'floor, lift usually out of order so take the stairs on the left',
        items: <PickupChecklistItem>[
          PickupChecklistItem(
            name: 'Bottle Gourd (Dudhi)',
            quantity: 1,
            unit: '450 gm',
          ),
          PickupChecklistItem(
            name: 'Onion(Kanda)',
            quantity: 1,
            unit: '250 gm',
          ),
          PickupChecklistItem(
            name: 'Tomato (Tameta)',
            quantity: 1,
            unit: '250 gm',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeDeliveryControllerProvider.overrideWith((Ref ref) => active),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showPickupChecklistSheet(
                      context,
                      'order-2',
                      verification,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // This is the exact failure mode a fixed-fraction item-list cap
      // missed: a tall customer card plus just 3 items still added up to
      // more than the sheet's real height, and there was nothing left for
      // the item list to shrink into. Flexible must make the item list
      // give up its own space first so the button is never the casualty.
      expect(find.text('Confirm Pickup').hitTestable(), findsOneWidget);
    },
  );
}
