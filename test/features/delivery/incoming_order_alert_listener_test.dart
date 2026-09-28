import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/alerts/alert_sound_player.dart';
import 'package:meet_commerce_rider_main/core/alerts/alert_vibration_player.dart';
import 'package:meet_commerce_rider_main/core/alerts/order_alert_notification.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/offers_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/presentation/incoming_order_alert_listener.dart';

/// Records calls instead of touching any real audio/vibration platform
/// channel — proves the *wiring* (start/stop called at the right moments),
/// not the platform plugins themselves, which is exactly the class of bug
/// (real code that looks right but was never actually exercised end to
/// end) this session's own vendor-app work found and fixed the same day.
class _FakeSoundPlayer implements AlertSoundPlayer {
  int playLoopCalls = 0;
  int stopCalls = 0;
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> playLoop() async {
    playLoopCalls++;
    _playing = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _playing = false;
  }

  @override
  void dispose() {}
}

class _FakeVibrationPlayer implements AlertVibrationPlayer {
  int startLoopCalls = 0;
  int stopCalls = 0;
  bool _vibrating = false;

  @override
  bool get isVibrating => _vibrating;

  @override
  Future<void> startLoop() async {
    startLoopCalls++;
    _vibrating = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _vibrating = false;
  }
}

class _FakeOrderAlertNotifier implements OrderAlertNotifier {
  int showCalls = 0;
  int cancelCalls = 0;
  String? lastTitle;
  String? lastBody;

  @override
  Future<void> show({required String title, required String body}) async {
    showCalls++;
    lastTitle = title;
    lastBody = body;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

DeliveryOrder _order(String id, AssignmentStatus status) => DeliveryOrder(
  orderId: id,
  orderNumber: id,
  assignmentStatus: status,
  totalAmount: 100.0,
  paymentMethod: 'ONLINE',
  riderEarning: 10.0,
  estimatedDuration: 10,
  customerAddress: DeliveryAddress(name: 'Customer', address: 'Addr'),
  storeAddress: DeliveryAddress(name: 'Store', address: 'Store Addr'),
  items: const <DeliveryItem>[],
);

void main() {
  late OffersController controller;
  late _FakeSoundPlayer sound;
  late _FakeVibrationPlayer vibration;
  late _FakeOrderAlertNotifier notification;

  setUp(() {
    controller = OffersController.local();
    sound = _FakeSoundPlayer();
    vibration = _FakeVibrationPlayer();
    notification = _FakeOrderAlertNotifier();
  });

  Widget harness() {
    return ProviderScope(
      overrides: [
        offersControllerProvider.overrideWith((Ref ref) => controller),
        alertSoundPlayerProvider.overrideWithValue(sound),
        alertVibrationPlayerProvider.overrideWithValue(vibration),
        orderAlertNotifierProvider.overrideWithValue(notification),
      ],
      child: const MaterialApp(
        home: IncomingOrderAlertListener(child: SizedBox.shrink()),
      ),
    );
  }

  testWidgets('no offer yet: alarm never starts', (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(sound.playLoopCalls, 0);
    expect(vibration.startLoopCalls, 0);
  });

  testWidgets(
    'a new incoming order starts the sound loop, the vibration loop, AND '
    'a real system notification, all in real time',
    (WidgetTester tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      await tester.pump();

      expect(sound.playLoopCalls, 1);
      expect(vibration.startLoopCalls, 1);
      expect(sound.stopCalls, 0);
      expect(vibration.stopCalls, 0);
      expect(notification.showCalls, 1);
      expect(notification.cancelCalls, 0);
      expect(notification.lastBody, contains('#o1'));
      expect(notification.lastBody, contains('₹10'));
    },
  );

  testWidgets(
    'the rider accepting the order stops the alarm in real time — this is '
    'the "if anyone accepts, it automatically closes" behaviour',
    (WidgetTester tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      await tester.pump();
      expect(sound.playLoopCalls, 1);

      controller.applyStatus('o1', AssignmentStatus.accepted);
      await tester.pump();

      expect(sound.stopCalls, 1);
      expect(vibration.stopCalls, 1);
      expect(notification.cancelCalls, 1);
    },
  );

  testWidgets(
    'the rider declining (removeOffer) stops the alarm — the "he can '
    'close it if he does not accept" behaviour',
    (WidgetTester tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      await tester.pump();
      expect(sound.playLoopCalls, 1);

      controller.removeOffer('o1');
      await tester.pump();

      expect(sound.stopCalls, 1);
      expect(vibration.stopCalls, 1);
    },
  );

  testWidgets(
    'an offer expiring or being taken by another process (order:expired / '
    'a realtime removal) stops the alarm the same way a decline does',
    (WidgetTester tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      await tester.pump();
      expect(sound.playLoopCalls, 1);

      controller.markExpired('o1');
      await tester.pump();

      expect(sound.stopCalls, 1);
      expect(vibration.stopCalls, 1);
    },
  );

  testWidgets(
    'after resolving, a fresh incoming order rings the alarm again — the '
    'stop is not a one-shot latch',
    (WidgetTester tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      await tester.pump();
      controller.removeOffer('o1');
      await tester.pump();
      expect(sound.playLoopCalls, 1);
      expect(sound.stopCalls, 1);

      controller.upsertOffer(_order('o2', AssignmentStatus.assigned));
      await tester.pump();

      expect(sound.playLoopCalls, 2);
      expect(vibration.startLoopCalls, 2);
    },
  );

  testWidgets(
    'an offer arriving while a delivery is already active never rings the '
    'alarm (R9.4 parity with the offer sheet suppression)',
    (WidgetTester tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      controller.upsertOffer(_order('active', AssignmentStatus.accepted));
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      await tester.pump();

      expect(sound.playLoopCalls, 0);
      expect(vibration.startLoopCalls, 0);
    },
  );

  testWidgets(
    'an offer already pending when the listener first mounts (e.g. a hot '
    'restart, or GET /delivery/orders reconciling before this widget '
    'attaches) still rings the alarm',
    (WidgetTester tester) async {
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(sound.playLoopCalls, 1);
      expect(vibration.startLoopCalls, 1);
      expect(notification.showCalls, 1);
    },
  );
}
