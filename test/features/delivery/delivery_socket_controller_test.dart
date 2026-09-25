import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/realtime/socket_client.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/delivery_socket_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/offers_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_repository.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';

import '../../helpers/fake_delivery_api.dart';
import '../../helpers/fake_socket_client.dart';

DeliveryOrder _order(
  String id, {
  required double customerLat,
  required double customerLng,
  DateTime? createdAt,
}) => DeliveryOrder(
  orderId: id,
  orderNumber: id,
  assignmentStatus: AssignmentStatus.inTransit,
  totalAmount: 100,
  paymentMethod: 'COD',
  riderEarning: 30,
  estimatedDuration: 10,
  customerAddress: DeliveryAddress(
    name: 'Customer',
    address: 'Addr',
    lat: customerLat,
    lng: customerLng,
  ),
  storeAddress: DeliveryAddress(name: 'Store', address: 'Store addr'),
  items: const <DeliveryItem>[],
  createdAt: createdAt,
);

void main() {
  group('DeliverySocketController single-order restore (blueprint §10)', () {
    test('a fresh reconcile sets the accepted/in-transit order as the '
        'single active delivery', () async {
      final FakeDeliveryApi api = FakeDeliveryApi();
      final DeliveryOrder active = _order(
        'active-1',
        customerLat: 22.51,
        customerLng: 88.31,
      );
      api.assignOrders(<DeliveryOrder>[active]);

      final DeliveryRepository repository = DeliveryRepository(api);
      final FakeSocketClient socket = FakeSocketClient();
      final ActiveDeliveryController activeDelivery = ActiveDeliveryController(
        repository: repository,
        socket: socket,
      );
      final OffersController offers = OffersController(
        repository: repository,
        socket: socket,
      );

      final DeliverySocketController controller = DeliverySocketController(
        socket: socket,
        offers: offers,
        activeDelivery: activeDelivery,
        repository: repository,
      );

      controller.start();
      // Reconcile is fire-and-forget from start(); let its Future settle.
      await pumpEventQueue();

      expect(activeDelivery.current?.orderId, 'active-1');

      await controller.dispose();
    });

    test(
      'a reconcile with no open order leaves the controller empty',
      () async {
        final FakeDeliveryApi api = FakeDeliveryApi();
        final DeliveryRepository repository = DeliveryRepository(api);
        final FakeSocketClient socket = FakeSocketClient();
        final ActiveDeliveryController activeDelivery =
            ActiveDeliveryController(repository: repository, socket: socket);
        final OffersController offers = OffersController(
          repository: repository,
          socket: socket,
        );

        final DeliverySocketController controller = DeliverySocketController(
          socket: socket,
          offers: offers,
          activeDelivery: activeDelivery,
          repository: repository,
        );

        controller.start();
        await pumpEventQueue();

        expect(activeDelivery.current, isNull);

        await controller.dispose();
      },
    );

    test('a different open order from the server replaces the tracked one '
        '(server is authoritative)', () async {
      final FakeDeliveryApi api = FakeDeliveryApi();
      final DeliveryOrder replaced = _order(
        'replaced',
        customerLat: 23.50,
        customerLng: 89.30,
      );
      final DeliveryOrder replacement = _order(
        'replacement',
        customerLat: 22.51,
        customerLng: 88.31,
      );

      final DeliveryRepository repository = DeliveryRepository(api);
      final FakeSocketClient socket = FakeSocketClient();
      final ActiveDeliveryController activeDelivery = ActiveDeliveryController(
        repository: repository,
        socket: socket,
      );
      activeDelivery.setActiveDelivery(replaced);

      final OffersController offers = OffersController(
        repository: repository,
        socket: socket,
      );

      final DeliverySocketController controller = DeliverySocketController(
        socket: socket,
        offers: offers,
        activeDelivery: activeDelivery,
        repository: repository,
      );

      // The server now lists a DIFFERENT open order (the previous one
      // went terminal server-side without this device hearing about it).
      api.assignOrders(<DeliveryOrder>[replacement]);

      controller.start();
      await pumpEventQueue();

      expect(activeDelivery.current?.orderId, 'replacement');

      await controller.dispose();
    });
  });

  group('DeliverySocketController reconcile prunes stale entries '
      '(regression: admin-cancelled order stuck until force-close)', () {
    test('the tracked order missing from a fresh /delivery/orders fetch is '
        'cleared from the active delivery', () async {
      final FakeDeliveryApi api = FakeDeliveryApi();
      final DeliveryOrder cancelled = _order(
        'cancelled-by-admin',
        customerLat: 23.50,
        customerLng: 89.30,
      );
      api.assignOrders(<DeliveryOrder>[cancelled]);

      final DeliveryRepository repository = DeliveryRepository(api);
      final FakeSocketClient socket = FakeSocketClient();
      final ActiveDeliveryController activeDelivery = ActiveDeliveryController(
        repository: repository,
        socket: socket,
      );
      final OffersController offers = OffersController(
        repository: repository,
        socket: socket,
      );

      final DeliverySocketController controller = DeliverySocketController(
        socket: socket,
        offers: offers,
        activeDelivery: activeDelivery,
        repository: repository,
      );

      controller.start();
      await pumpEventQueue();
      expect(activeDelivery.current?.orderId, 'cancelled-by-admin');

      // Admin cancels 'cancelled-by-admin' from the dashboard while
      // this device's socket connection missed (or never got) the
      // live order:status event — the backend endpoint simply stops
      // listing it once it's terminal, and no other order exists.
      api.assignOrders(<DeliveryOrder>[]);

      await controller.refreshOrders();

      expect(
        activeDelivery.current,
        isNull,
        reason:
            'a manual refresh must prune a tracked order no longer open on '
            'the server',
      );

      await controller.dispose();
    });

    test(
      'a stale offer no longer present on refresh is removed from the offers list',
      () async {
        final FakeDeliveryApi api = FakeDeliveryApi();
        final DeliveryRepository repository = DeliveryRepository(api);
        final FakeSocketClient socket = FakeSocketClient();
        final ActiveDeliveryController activeDelivery =
            ActiveDeliveryController(repository: repository, socket: socket);
        final OffersController offers = OffersController(
          repository: repository,
          socket: socket,
        );

        final DeliverySocketController controller = DeliverySocketController(
          socket: socket,
          offers: offers,
          activeDelivery: activeDelivery,
          repository: repository,
        );

        controller.start();
        await pumpEventQueue();

        // An offer arrives live via socket (not yet accepted, so it
        // lands in OffersController, not the active-delivery batch).
        final DeliveryOrder offer = _order(
          'offer-1',
          customerLat: 22.51,
          customerLng: 88.31,
        ).copyWith(assignmentStatus: AssignmentStatus.assigned);
        offers.upsertOffer(offer);
        expect(offers.offers, hasLength(1));

        // The offer expires/gets reassigned elsewhere before the rider
        // accepts it — a fresh fetch no longer lists it at all.
        await controller.refreshOrders();

        expect(
          offers.offers,
          isEmpty,
          reason:
              'a stale offer must not linger after a refresh confirms it is gone',
        );

        await controller.dispose();
      },
    );
  });

  group('DeliverySocketController live order:status payload (regression: '
      'the backend field is `status`, never `assignmentStatus` — this '
      'silently no-opped every live admin-triggered update since the '
      'field name was never actually checked against a real payload)', () {
    test('a live order:status event with the real backend payload shape '
        '(status, not assignmentStatus) removes the order immediately, '
        'with no refresh involved', () async {
      final FakeDeliveryApi api = FakeDeliveryApi();
      final DeliveryOrder inTransitOrder = _order(
        'order-live-1',
        customerLat: 22.51,
        customerLng: 88.31,
      );
      api.assignOrders(<DeliveryOrder>[inTransitOrder]);
      final DeliveryRepository repository = DeliveryRepository(api);
      final FakeSocketClient socket = FakeSocketClient();
      final ActiveDeliveryController activeDelivery = ActiveDeliveryController(
        repository: repository,
        socket: socket,
      );
      final OffersController offers = OffersController(
        repository: repository,
        socket: socket,
      );

      final DeliverySocketController controller = DeliverySocketController(
        socket: socket,
        offers: offers,
        activeDelivery: activeDelivery,
        repository: repository,
      );

      controller.start();
      await pumpEventQueue();
      expect(activeDelivery.byId('order-live-1'), isNotNull);

      // Exactly the shape emitOrderUpdate/_emitOrderStatus send on the
      // backend: {orderId, orderNumber, status, message, timestamp}.
      // No `assignmentStatus` key at all.
      socket.pushEvent('order:status', <String, dynamic>{
        'orderId': 'order-live-1',
        'orderNumber': 'order-live-1',
        'status': 'DELIVERED',
        'message': 'Order delivered successfully',
      });
      await pumpEventQueue();

      expect(
        activeDelivery.byId('order-live-1'),
        isNull,
        reason:
            'a live order:status push must remove the order without '
            'any manual refresh or app reopen',
      );

      await controller.dispose();
    });

    test('an admin cancelling an order the rider only ever ACCEPTED (never '
        'picked up) still removes it live, even though CANCELLED is not a '
        'legal next step from ACCEPTED in the rider-driven walk', () async {
      final FakeDeliveryApi api = FakeDeliveryApi();
      final DeliveryOrder accepted = _order(
        'order-live-2',
        customerLat: 22.51,
        customerLng: 88.31,
      ).copyWith(assignmentStatus: AssignmentStatus.accepted);
      api.assignOrders(<DeliveryOrder>[accepted]);
      final DeliveryRepository repository = DeliveryRepository(api);
      final FakeSocketClient socket = FakeSocketClient();
      final ActiveDeliveryController activeDelivery = ActiveDeliveryController(
        repository: repository,
        socket: socket,
      );
      final OffersController offers = OffersController(
        repository: repository,
        socket: socket,
      );

      final DeliverySocketController controller = DeliverySocketController(
        socket: socket,
        offers: offers,
        activeDelivery: activeDelivery,
        repository: repository,
      );

      controller.start();
      await pumpEventQueue();
      expect(
        activeDelivery.current?.assignmentStatus,
        AssignmentStatus.accepted,
      );

      socket.pushEvent('order:status', <String, dynamic>{
        'orderId': 'order-live-2',
        'status': 'CANCELLED',
      });
      await pumpEventQueue();

      expect(
        activeDelivery.byId('order-live-2'),
        isNull,
        reason:
            'a server-reported terminal status must always win, '
            'even from a stage the rider-driven walk would reject',
      );

      await controller.dispose();
    });
  });

  group('DeliverySocketController reconciles on socket reconnect (regression: '
      'a WebSocket drop/reconnect while the app stays in the foreground '
      'never fires AppLifecycleState.resumed, so an order:status event '
      'lost during that gap would otherwise sit stuck until the rider '
      'manually refreshes or force-closes the app)', () {
    test('an order that went terminal while the socket was down is pruned '
        'the moment the socket reconnects, with no lifecycle event and no '
        'manual refresh', () async {
      final FakeDeliveryApi api = FakeDeliveryApi();
      final DeliveryOrder order = _order(
        'order-reconnect-1',
        customerLat: 22.51,
        customerLng: 88.31,
      );
      api.assignOrders(<DeliveryOrder>[order]);

      final DeliveryRepository repository = DeliveryRepository(api);
      final FakeSocketClient socket = FakeSocketClient(
        status: SocketStatus.connected,
      );
      final ActiveDeliveryController activeDelivery = ActiveDeliveryController(
        repository: repository,
        socket: socket,
      );
      final OffersController offers = OffersController(
        repository: repository,
        socket: socket,
      );

      final DeliverySocketController controller = DeliverySocketController(
        socket: socket,
        offers: offers,
        activeDelivery: activeDelivery,
        repository: repository,
      );

      controller.start();
      await pumpEventQueue();
      expect(activeDelivery.byId('order-reconnect-1'), isNotNull);

      // The WebSocket transport drops (network blip, ping timeout,
      // battery-optimization throttling) — the app is still in the
      // foreground the whole time.
      socket.fakeStatus = SocketStatus.disconnected;
      await pumpEventQueue();

      // While disconnected, admin marks the order delivered. The
      // live order:status event is gone — nothing is listening — but
      // the server-side source of truth (what a fresh GET returns)
      // has already moved on, exactly like the real backend endpoint
      // that stops listing terminal orders.
      api.assignOrders(<DeliveryOrder>[]);

      // The transport quietly re-establishes on its own.
      socket.fakeStatus = SocketStatus.connected;
      await pumpEventQueue();

      expect(
        activeDelivery.byId('order-reconnect-1'),
        isNull,
        reason:
            'reconnecting must trigger the same reconcile as an '
            'app-foreground resume — the rider should never have to '
            'manually refresh to see this',
      );

      await controller.dispose();
    });
  });
}
