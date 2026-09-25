import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/network/api_exception.dart';
import 'package:meet_commerce_rider_main/core/realtime/socket_client.dart';
import 'package:meet_commerce_rider_main/core/realtime/socket_events.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/offers_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_repository.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_socket_client.dart';

class _MockDeliveryRepository extends Mock implements DeliveryRepository {}

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

  setUp(() {
    controller = OffersController.local();
  });

  tearDown(() {
    controller.dispose();
  });

  // -------------------------------------------------------------------------
  // upsertOffer
  // -------------------------------------------------------------------------
  group('upsertOffer', () {
    test('adds a new offer when list is empty', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      expect(controller.offers, hasLength(1));
      expect(controller.offers.first.orderId, 'o1');
    });

    test('replaces an existing offer with the same orderId', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      controller.upsertOffer(_order('o1', AssignmentStatus.accepted));
      expect(controller.offers, hasLength(1));
      expect(
        controller.offers.first.assignmentStatus,
        AssignmentStatus.accepted,
      );
    });

    test('notifies listeners on add', () {
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      expect(notified, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // removeOffer / markExpired
  // -------------------------------------------------------------------------
  group('removeOffer / markExpired', () {
    test('removes by orderId and notifies', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.removeOffer('o1');
      expect(controller.offers, isEmpty);
      expect(notified, isTrue);
    });

    test('removeOffer is a no-op when orderId not found', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.removeOffer('ghost');
      expect(controller.offers, hasLength(1));
      expect(notified, isFalse);
    });

    test('markExpired removes the offer', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      controller.markExpired('o1');
      expect(controller.offers, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // applyStatus – legal, terminal and illegal transitions
  // -------------------------------------------------------------------------
  group('applyStatus', () {
    test('legal transitions go through AssignmentStateMachine.apply', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      controller.applyStatus('o1', AssignmentStatus.accepted);
      expect(
        controller.offers.first.assignmentStatus,
        AssignmentStatus.accepted,
      );
    });

    test('terminal transitions remove the offer', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.inTransit));
      controller.applyStatus('o1', AssignmentStatus.delivered);
      expect(controller.offers, isEmpty);
    });

    test('illegal transitions are rejected (state unchanged)', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.accepted));
      bool notified = false;
      controller.addListener(() => notified = true);
      // Illegal: accepted → assigned
      controller.applyStatus('o1', AssignmentStatus.assigned);
      expect(
        controller.offers.first.assignmentStatus,
        AssignmentStatus.accepted,
      );
      expect(notified, isFalse);
    });

    test('no-op when orderId not found', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.applyStatus('ghost', AssignmentStatus.accepted);
      expect(notified, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // hasActiveDelivery
  // -------------------------------------------------------------------------
  group('hasActiveDelivery (R9.4)', () {
    test('false when all offers are assigned', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
      expect(controller.hasActiveDelivery, isFalse);
    });

    test('true when any offer is accepted', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.accepted));
      expect(controller.hasActiveDelivery, isTrue);
    });

    test('true when any offer is inTransit', () {
      controller.upsertOffer(_order('o1', AssignmentStatus.inTransit));
      expect(controller.hasActiveDelivery, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // offers list immutability
  // -------------------------------------------------------------------------
  test('offers list is unmodifiable', () {
    controller.upsertOffer(_order('o1', AssignmentStatus.assigned));
    expect(
      () => controller.offers.add(_order('o2', AssignmentStatus.assigned)),
      throwsUnsupportedError,
    );
  });

  // -------------------------------------------------------------------------
  // acceptOffer
  // -------------------------------------------------------------------------
  group('acceptOffer', () {
    late _MockDeliveryRepository repo;
    late FakeSocketClient socket;
    late OffersController net;

    setUp(() {
      repo = _MockDeliveryRepository();
      socket = FakeSocketClient();
      net = OffersController(repository: repo, socket: socket);
    });

    tearDown(() => net.dispose());

    test('success: transitions to accepted, emits order:track', () async {
      net.upsertOffer(_order('o1', AssignmentStatus.assigned));
      when(
        () => repo.acceptOrder('o1'),
      ).thenAnswer((_) async => <String, dynamic>{});

      socket.fakeStatus = SocketStatus.connected;
      final OfferActionResult result = await net.acceptOffer('o1');

      expect(result, isA<OfferActionSuccess>());
      expect(net.offers.first.assignmentStatus, AssignmentStatus.accepted);
      expect(socket.emittedEvents, hasLength(1));
      expect(socket.emittedEvents.single.event, SocketEvents.orderTrack);
      expect(socket.emittedEvents.single.payload['orderId'], 'o1');
    });

    test('busy flag is set during the call and cleared afterwards', () async {
      net.upsertOffer(_order('o1', AssignmentStatus.assigned));
      final Completer<Map<String, dynamic>> completer =
          Completer<Map<String, dynamic>>();
      when(() => repo.acceptOrder('o1')).thenAnswer((_) => completer.future);

      final Future<OfferActionResult> future = net.acceptOffer('o1');
      expect(net.isBusy('o1'), isTrue);

      completer.complete(<String, dynamic>{});
      await future;
      expect(net.isBusy('o1'), isFalse);
    });

    test(
      'OrderNotAvailableException → OfferAlreadyTaken, offer removed',
      () async {
        net.upsertOffer(_order('o1', AssignmentStatus.assigned));
        when(() => repo.acceptOrder('o1')).thenThrow(
          const OrderNotAvailableException('Order is no longer available'),
        );

        final OfferActionResult result = await net.acceptOffer('o1');

        expect(result, isA<OfferAlreadyTaken>());
        expect(net.offers, isEmpty);
      },
    );

    test('ApiConflictException → OfferAlreadyTaken, offer removed', () async {
      net.upsertOffer(_order('o1', AssignmentStatus.assigned));
      when(() => repo.acceptOrder('o1')).thenThrow(
        const ApiConflictException(
          'Order was already taken',
          statusCode: 409,
          backendCode: 'ORDER_NOT_AVAILABLE',
        ),
      );

      final OfferActionResult result = await net.acceptOffer('o1');

      expect(result, isA<OfferAlreadyTaken>());
      expect(net.offers, isEmpty);
    });

    test('generic failure → OfferActionFailure, offer stays', () async {
      net.upsertOffer(_order('o1', AssignmentStatus.assigned));
      when(
        () => repo.acceptOrder('o1'),
      ).thenThrow(const ApiNetworkException('offline'));

      final OfferActionResult result = await net.acceptOffer('o1');

      expect(result, isA<OfferActionFailure>());
      expect(net.offers, hasLength(1));
    });

    test('does not emit order:track when socket is disconnected', () async {
      net.upsertOffer(_order('o1', AssignmentStatus.assigned));
      socket.fakeStatus = SocketStatus.disconnected;
      when(
        () => repo.acceptOrder('o1'),
      ).thenAnswer((_) async => <String, dynamic>{});

      final OfferActionResult result = await net.acceptOffer('o1');

      expect(result, isA<OfferActionSuccess>());
      expect(socket.emittedEvents, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // rejectOffer
  // -------------------------------------------------------------------------
  group('rejectOffer', () {
    late _MockDeliveryRepository repo;
    late FakeSocketClient socket;
    late OffersController net;

    setUp(() {
      repo = _MockDeliveryRepository();
      socket = FakeSocketClient();
      net = OffersController(repository: repo, socket: socket);
    });

    tearDown(() => net.dispose());

    test('success: removes the offer locally', () async {
      net.upsertOffer(_order('o1', AssignmentStatus.assigned));
      when(
        () => repo.rejectOrder('o1', RejectReason.tooFar.wire),
      ).thenAnswer((_) async {});

      final OfferActionResult result = await net.rejectOffer(
        'o1',
        RejectReason.tooFar,
      );

      expect(result, isA<OfferActionSuccess>());
      expect(net.offers, isEmpty);
    });

    test(
      'OrderNotAvailableException → OfferAlreadyTaken, offer removed',
      () async {
        net.upsertOffer(_order('o1', AssignmentStatus.assigned));
        when(
          () => repo.rejectOrder('o1', RejectReason.other.wire),
        ).thenThrow(const OrderNotAvailableException());

        final OfferActionResult result = await net.rejectOffer(
          'o1',
          RejectReason.other,
        );

        expect(result, isA<OfferAlreadyTaken>());
        expect(net.offers, isEmpty);
      },
    );

    test('generic failure leaves the offer in the list', () async {
      net.upsertOffer(_order('o1', AssignmentStatus.assigned));
      when(
        () => repo.rejectOrder('o1', RejectReason.vehicleIssue.wire),
      ).thenThrow(const ApiServerException('boom', statusCode: 500));

      final OfferActionResult result = await net.rejectOffer(
        'o1',
        RejectReason.vehicleIssue,
      );

      expect(result, isA<OfferActionFailure>());
      expect(net.offers, hasLength(1));
    });
  });
}
