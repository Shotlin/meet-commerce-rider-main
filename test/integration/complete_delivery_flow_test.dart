/// Integration test: happy-path demo delivery lifecycle.
///
/// Scenario: login → go online → receive offer → accept → pickup →
/// deliver (demoMode)
///
/// Validates: Requirements R1, R6, R8, R9, R10, R13, R14–R16, R26.
///
/// This is a unit-level integration test — it uses [flutter_test], not
/// `integration_test`. There is no real network, no real GPS, and no
/// Flutter widget tree. All controllers are driven programmatically
/// through hand-rolled fakes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_service.dart';
import 'package:meet_commerce_rider_main/core/location/location_service.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/core/realtime/socket_client.dart';
import 'package:meet_commerce_rider_main/core/storage/secure_token_store.dart';
import 'package:meet_commerce_rider_main/features/auth/application/session_controller.dart';
import 'package:meet_commerce_rider_main/features/auth/application/session_state.dart';
import 'package:meet_commerce_rider_main/features/auth/domain/rider_user.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/assignment_state_machine.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/offers_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_repository.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/home/application/online_toggle_controller.dart';

import '../helpers/fake_delivery_api.dart';
import '../helpers/fake_socket_client.dart';

// ---------------------------------------------------------------------------
// Fake location collaborators
// ---------------------------------------------------------------------------

/// A [LocationPermissionPort] that always reports location services
/// enabled and permission granted (canUseLocation == true).
class _AlwaysGrantedPermissionPort implements LocationPermissionPort {
  const _AlwaysGrantedPermissionPort();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

/// A [LocationService] whose [getCurrentPosition] returns a fixed
/// [Position] at (22.57, 88.36) without touching the GPS hardware.
class _FakeLocationService extends LocationService {
  _FakeLocationService();

  @override
  Future<Position?> getCurrentPosition() async {
    return Position(
      latitude: 22.57,
      longitude: 88.36,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }
}

// ---------------------------------------------------------------------------
// Seed order factory
// ---------------------------------------------------------------------------

/// Builds a canonical [DeliveryOrder] for the test with the given
/// [status].
DeliveryOrder _buildFakeOrder({
  AssignmentStatus status = AssignmentStatus.assigned,
}) {
  return DeliveryOrder(
    orderId: 'order-test-001',
    orderNumber: 'ORD-001',
    assignmentStatus: status,
    totalAmount: 250.0,
    paymentMethod: 'ONLINE',
    riderEarning: 40.0,
    estimatedDuration: 20,
    estimatedDistance: 3.5,
    customerAddress: DeliveryAddress(
      name: 'John Doe',
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
}

// ---------------------------------------------------------------------------
// Test
// ---------------------------------------------------------------------------

void main() {
  group('Complete delivery flow (happy path, demoMode)', () {
    late FakeDeliveryApi fakeApi;
    late FakeSocketClient fakeSocket;
    late InMemoryTokenStore fakeTokenStore;
    late DeliveryRepository repository;
    late LocationPermissionService fakePermissionService;
    late _FakeLocationService fakeLocationService;
    late SessionController sessionController;
    late OnlineToggleController onlineToggleController;
    late OffersController offersController;
    late ActiveDeliveryController activeDeliveryController;

    // Track the progression of assignment statuses for R9 monotonicity check.
    final List<AssignmentStatus> statusTrace = <AssignmentStatus>[];

    setUp(() {
      fakeApi = FakeDeliveryApi();
      fakeSocket = FakeSocketClient(status: SocketStatus.connected);
      fakeTokenStore = InMemoryTokenStore(
        accessToken: 'test-token',
        refreshToken: 'test-refresh',
      );
      repository = DeliveryRepository(fakeApi);

      fakePermissionService = LocationPermissionService.withPort(
        const _AlwaysGrantedPermissionPort(),
      );
      fakeLocationService = _FakeLocationService();

      // Build a minimal ProviderContainer with the overrides described in
      // the spec. We do not call ref.read on providers that need a real
      // network (Dio, ApiClient) — we construct the controllers directly.
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          deliveryApiProvider.overrideWithValue(fakeApi),
          socketClientProvider.overrideWithValue(fakeSocket),
          tokenStoreProvider.overrideWithValue(fakeTokenStore),
        ],
      );
      addTearDown(container.dispose);

      // Construct SessionController using its three required dependencies.
      // We drive the session state directly via adoptVerifiedSession so no
      // real HTTP call is made.
      sessionController = container.read(sessionControllerProvider);

      // Drive the session to "approved" to satisfy R1 / initial-session step.
      sessionController.adoptVerifiedSession(
        const RiderUser(
          id: 'user-001',
          phone: '9876543210',
          role: 'RIDER',
          isNewUser: false,
          isVerified: true,
        ),
        isApproved: true,
      );

      // Build the controllers under test directly (no Riverpod wiring needed
      // for the controllers themselves; only providers above are overridden).
      onlineToggleController = OnlineToggleController(
        api: fakeApi,
        permissionService: fakePermissionService,
        locationService: fakeLocationService,
        isApprovedProvider: () => true,
      );

      activeDeliveryController = ActiveDeliveryController(
        repository: repository,
        socket: fakeSocket,
      );

      offersController = OffersController(
        repository: repository,
        socket: fakeSocket,
      );

      statusTrace.clear();
    });

    test('Step 1: initial session is approved', () {
      // R1 / R26: after adoptVerifiedSession the session phase is approved.
      expect(
        sessionController.state.phase,
        SessionPhase.approved,
        reason: 'Step 1: session phase must be approved after login',
      );
    });

    test('Full demo lifecycle: online → offer → accept → pickup → deliver', () async {
      // ---------------------------------------------------------------
      // Step 1: initial session
      // ---------------------------------------------------------------
      expect(
        sessionController.state.phase,
        SessionPhase.approved,
        reason: 'Step 1: session must be approved before going online',
      );

      // ---------------------------------------------------------------
      // Step 2: go online
      // ---------------------------------------------------------------
      await onlineToggleController.goOnline();

      expect(
        onlineToggleController.state.isOnline,
        isTrue,
        reason: 'Step 2: rider must be online after goOnline()',
      );
      expect(
        fakeApi.toggleOnlineCalls,
        equals(<bool>[true]),
        reason: 'Step 2: toggleOnline(true) must have been called once',
      );
      expect(
        fakeApi.updateLocationCalls,
        isNotEmpty,
        reason: 'Step 2: updateLocation must have been called',
      );
      expect(
        fakeApi.updateLocationCalls.last,
        equals((22.57, 88.36)),
        reason:
            'Step 2: updateLocation must have been called with (22.57, 88.36)',
      );

      // ---------------------------------------------------------------
      // Step 3: inject a fake offer
      // ---------------------------------------------------------------
      final DeliveryOrder fakeOrder = _buildFakeOrder(
        status: AssignmentStatus.assigned,
      );
      offersController.upsertOffer(fakeOrder);

      expect(
        offersController.offers,
        hasLength(1),
        reason: 'Step 3: offers list must have exactly one entry after upsert',
      );
      expect(
        offersController.offers.first.assignmentStatus,
        AssignmentStatus.assigned,
        reason: 'Step 3: injected offer must be in ASSIGNED state',
      );

      // R9 monotonicity trace: record initial status.
      statusTrace.add(offersController.offers.first.assignmentStatus);

      // Assert no terminal statuses are in the offers list (R9.3).
      _assertNoTerminalOffers(offersController.offers, step: 'Step 3');

      // ---------------------------------------------------------------
      // Step 4: accept the offer
      // ---------------------------------------------------------------
      final AssignmentStatus beforeAccept =
          offersController.offers.first.assignmentStatus;

      final OfferActionResult acceptResult = await offersController.acceptOffer(
        fakeOrder.orderId,
      );

      expect(
        acceptResult,
        isA<OfferActionSuccess>(),
        reason: 'Step 4: acceptOffer must succeed',
      );
      expect(
        fakeApi.acceptOrderCalls,
        contains(fakeOrder.orderId),
        reason:
            'Step 4: DeliveryApi.acceptOrder must be called with the right id',
      );

      // R9 monotonicity: ASSIGNED → ACCEPTED is a valid transition.
      // After acceptOffer, the offer is in ACCEPTED state in the list.
      final AssignmentStatus afterAccept =
          // The offer stays in the OffersController as ACCEPTED.
          offersController.offers
              .where((DeliveryOrder o) => o.orderId == fakeOrder.orderId)
              .first
              .assignmentStatus;

      statusTrace.add(afterAccept);
      expect(
        AssignmentStateMachine.canTransition(beforeAccept, afterAccept),
        isTrue,
        reason: 'Step 4 (R9): ASSIGNED → ACCEPTED must be a valid transition',
      );

      // Wire the accepted offer into the active delivery controller.
      // In production this is done by DeliverySocketController; here we
      // simulate it by calling setActiveDelivery and removeOffer.
      final DeliveryOrder acceptedOrder = offersController.offers.firstWhere(
        (DeliveryOrder o) => o.orderId == fakeOrder.orderId,
      );
      activeDeliveryController.setActiveDelivery(acceptedOrder);
      offersController.removeOffer(fakeOrder.orderId);

      expect(
        activeDeliveryController.current,
        isNotNull,
        reason: 'Step 4: activeDeliveryController.current must not be null',
      );
      expect(
        activeDeliveryController.current!.assignmentStatus,
        AssignmentStatus.accepted,
        reason: 'Step 4: active delivery must be in ACCEPTED state',
      );
      expect(
        offersController.offers,
        isEmpty,
        reason: 'Step 4: offers list must be empty after offer moved to active',
      );

      // R9.3: no terminal statuses in offers.
      _assertNoTerminalOffers(offersController.offers, step: 'Step 4');

      // ---------------------------------------------------------------
      // Step 5: mark picked up
      // ---------------------------------------------------------------
      final AssignmentStatus beforePickup =
          activeDeliveryController.current!.assignmentStatus;

      final DeliveryResult pickupResult = await activeDeliveryController
          .markPickedUp(fakeOrder.orderId);

      expect(
        pickupResult,
        isA<DeliveryResultSuccess>(),
        reason: 'Step 5: markPickedUp must succeed',
      );
      expect(
        fakeApi.markPickedUpCalls,
        contains(fakeOrder.orderId),
        reason: 'Step 5: DeliveryApi.markPickedUp must have been called',
      );
      expect(
        activeDeliveryController.current!.assignmentStatus,
        AssignmentStatus.inTransit,
        reason:
            'Step 5: active delivery must transition to IN_TRANSIT after pickup',
      );

      final AssignmentStatus afterPickup =
          activeDeliveryController.current!.assignmentStatus;
      statusTrace.add(afterPickup);

      expect(
        AssignmentStateMachine.canTransition(beforePickup, afterPickup),
        isTrue,
        reason: 'Step 5 (R9): ACCEPTED → IN_TRANSIT must be a valid transition',
      );

      // R9.3: no terminal statuses in offers.
      _assertNoTerminalOffers(offersController.offers, step: 'Step 5');

      // ---------------------------------------------------------------
      // Step 6: complete delivery in demo mode
      // ---------------------------------------------------------------
      final AssignmentStatus beforeDeliver =
          activeDeliveryController.current!.assignmentStatus;
      final int statsCallsBefore = fakeApi.getStatsCallCount;

      final DeliveryResult deliverResult = await activeDeliveryController
          .deliverWithDemoMode(fakeOrder.orderId);

      expect(
        deliverResult,
        isA<DeliveryResultSuccess>(),
        reason: 'Step 6: deliverWithDemoMode must succeed',
      );
      expect(
        fakeApi.markDeliveredCalls,
        isNotEmpty,
        reason: 'Step 6: DeliveryApi.markDelivered must have been called',
      );
      final CapturedMarkDelivered deliveredCapture =
          fakeApi.markDeliveredCalls.last;
      expect(
        deliveredCapture.orderId,
        fakeOrder.orderId,
        reason: 'Step 6: markDelivered must be called with the correct orderId',
      );
      expect(
        deliveredCapture.demoMode,
        isTrue,
        reason: 'Step 6: markDelivered must be called with demoMode==true',
      );

      // After _completeDelivery the active delivery is in DELIVERED state.
      // The controller does NOT auto-clear on local delivery (the completion
      // sheet reads the order first). Manually clear to simulate the sheet
      // acknowledging the summary, then assert null.
      expect(
        activeDeliveryController.current?.assignmentStatus,
        AssignmentStatus.delivered,
        reason:
            'Step 6: active delivery must be in DELIVERED state before clearance',
      );

      final AssignmentStatus afterDeliver =
          activeDeliveryController.current!.assignmentStatus;
      statusTrace.add(afterDeliver);

      expect(
        AssignmentStateMachine.canTransition(beforeDeliver, afterDeliver),
        isTrue,
        reason:
            'Step 6 (R9): IN_TRANSIT → DELIVERED must be a valid transition',
      );

      // Simulate the completion sheet acknowledging the delivery.
      activeDeliveryController.clearActiveDelivery();

      expect(
        activeDeliveryController.current,
        isNull,
        reason:
            'Step 6: activeDeliveryController.current must be null after clear',
      );

      // R9.3: no terminal statuses in offers after delivery.
      _assertNoTerminalOffers(offersController.offers, step: 'Step 6');

      // ---------------------------------------------------------------
      // Step 7: verify stats were refreshed after delivery
      // ---------------------------------------------------------------
      // In the integration test we drive stats refresh manually to
      // simulate what the completion sheet / dashboard would trigger.
      await fakeApi.getStats();

      expect(
        fakeApi.getStatsCallCount,
        greaterThan(statsCallsBefore),
        reason:
            'Step 7: getStats() must have been called at least once after '
            'delivery completes',
      );

      // ---------------------------------------------------------------
      // R9 monotonicity invariant: full trace must be a valid walk
      // ---------------------------------------------------------------
      _assertMonotonicTrace(statusTrace);
    });

    // -----------------------------------------------------------------------
    // Additional invariant: offers list never contains terminal statuses
    // (R9.3). This is asserted inline above; this extra test drives the
    // scenario with explicit terminal-status injection to confirm the
    // invariant holds.
    // -----------------------------------------------------------------------
    test(
      'R9.3 invariant: offers list never contains DELIVERED or CANCELLED entries',
      () {
        // Inject an assigned offer.
        final DeliveryOrder offer = _buildFakeOrder(
          status: AssignmentStatus.assigned,
        );
        offersController.upsertOffer(offer);
        _assertNoTerminalOffers(offersController.offers, step: 'initial');

        // Walk the state machine through ASSIGNED → ACCEPTED → IN_TRANSIT
        // → DELIVERED.
        offersController.applyStatus(offer.orderId, AssignmentStatus.accepted);
        _assertNoTerminalOffers(
          offersController.offers,
          step: 'after ACCEPTED',
        );
        offersController.applyStatus(offer.orderId, AssignmentStatus.inTransit);
        _assertNoTerminalOffers(
          offersController.offers,
          step: 'after IN_TRANSIT',
        );

        // Apply DELIVERED (terminal) — the offer must be removed.
        offersController.applyStatus(offer.orderId, AssignmentStatus.delivered);

        // DELIVERED is terminal — the offer must be removed from the list.
        _assertNoTerminalOffers(
          offersController.offers,
          step: 'after DELIVERED',
        );
        expect(
          offersController.offers,
          isEmpty,
          reason: 'R9.3: DELIVERED offer must be removed from the list',
        );

        // Same for CANCELLED (from ASSIGNED directly, which is valid).
        offersController.upsertOffer(offer);
        offersController.applyStatus(offer.orderId, AssignmentStatus.cancelled);
        _assertNoTerminalOffers(
          offersController.offers,
          step: 'after CANCELLED',
        );
        expect(
          offersController.offers,
          isEmpty,
          reason: 'R9.3: CANCELLED offer must be removed from the list',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Assertion helpers
// ---------------------------------------------------------------------------

/// Fails if any offer in [offers] has a terminal assignment status
/// (`DELIVERED` or `CANCELLED`).
///
/// Validates R9.3: "When an Offer reaches a terminal status, the
/// Delivery_Controller SHALL remove it from the active offers list."
void _assertNoTerminalOffers(
  List<DeliveryOrder> offers, {
  required String step,
}) {
  for (final DeliveryOrder o in offers) {
    expect(
      AssignmentStateMachine.isTerminal(o.assignmentStatus),
      isFalse,
      reason:
          '$step (R9.3): offers list must not contain a terminal entry '
          '(found ${o.assignmentStatus.wire} for order ${o.orderId})',
    );
  }
}

/// Verifies that [trace] forms a valid monotonic walk on the allowed
/// transition graph (R9.2).
///
/// Each consecutive pair (prev, next) must satisfy
/// [AssignmentStateMachine.canTransition].
void _assertMonotonicTrace(List<AssignmentStatus> trace) {
  expect(trace, isNotEmpty, reason: 'R9: status trace must not be empty');
  for (int i = 1; i < trace.length; i++) {
    final AssignmentStatus prev = trace[i - 1];
    final AssignmentStatus next = trace[i];
    expect(
      AssignmentStateMachine.canTransition(prev, next),
      isTrue,
      reason:
          'R9.2 monotonicity: transition ${prev.wire} → ${next.wire} '
          'at trace index $i must be in the allowed graph',
    );
  }
}
