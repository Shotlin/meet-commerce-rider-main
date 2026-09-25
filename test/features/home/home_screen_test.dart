import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:meet_commerce_rider_main/core/location/location_display_provider.dart';
import 'package:meet_commerce_rider_main/core/location/location_lifecycle_manager.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_service.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_status.dart';
import 'package:meet_commerce_rider_main/core/location/location_profile.dart';
import 'package:meet_commerce_rider_main/core/location/location_service.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_controller.dart';
import 'package:meet_commerce_rider_main/features/home/application/home_dashboard_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/offers_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/pickup_session_controller.dart';
import 'package:meet_commerce_rider_main/features/home/application/online_toggle_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_repository.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_earnings.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_earnings.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_profile.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_stats.dart';
import 'package:meet_commerce_rider_main/features/home/presentation/home_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_delivery_api.dart';
import '../../helpers/fake_socket_client.dart';

class _MockLocationService extends Mock implements LocationService {}

class _MockLocationPermissionService extends Mock
    implements LocationPermissionService {}

/// Overrides [FakeDeliveryApi]'s fixed seeds so each home state can
/// control exactly what `/delivery/profile|stats|earnings` return.
class _HomeApi extends FakeDeliveryApi {
  _HomeApi({RiderProfile? profile, RiderStats? stats, RiderEarnings? earnings})
    : _profile = profile,
      _stats = stats,
      _earnings = earnings;

  final RiderProfile? _profile;
  final RiderStats? _stats;
  final RiderEarnings? _earnings;

  @override
  Future<RiderProfile> getProfile() async => _profile ?? super.getProfile();

  @override
  Future<RiderStats> getStats() async => _stats ?? super.getStats();

  @override
  Future<RiderEarnings> getEarnings(EarningsPeriod period) async =>
      _earnings ?? super.getEarnings(period);
}

class _FixedLocationDisplay extends LocationDisplayNotifier {
  @override
  Future<LocationDisplay?> build() async {
    return const LocationDisplay(
      position: GeoPoint(22.5726, 88.3639),
      areaName: 'Bow Bazar, Kolkata',
    );
  }
}

RiderProfile _profile({bool isOnline = false}) => RiderProfile(
  id: 'profile-1',
  userId: 'user-1',
  isApproved: true,
  isOnline: isOnline,
  rating: 4.6,
  totalDeliveries: 128,
  commissionRate: 15,
  name: 'Sayan Mondal',
  phone: '9876543210',
);

RiderStats _stats({int deliveredToday = 6, double rating = 4.6}) => RiderStats(
  totalAssigned: 130,
  totalDelivered: 128,
  deliveredToday: deliveredToday,
  deliveriesToday: deliveredToday,
  totalEarnings: 12480,
  earningsToday: 540,
  earningsThisWeek: 3210,
  weeklyData: const <DailyStats>[],
  rating: rating,
  totalDeliveries: 128,
  acceptanceRate: 96,
  dailyTarget: 10,
);

RiderEarnings _earnings({double pendingPayout = 320}) => RiderEarnings(
  period: 'today',
  totalEarnings: 540,
  deliveriesCount: 6,
  avgPerDelivery: 90,
  breakdown: const EarningsBreakdown(
    baseDeliveryFees: 480,
    distanceBonus: 40,
    performanceBonus: 0,
    tips: 20,
  ),
  dailyBreakdown: const <DailyEarning>[],
  pendingPayout: pendingPayout,
  alreadyPaid: 12160,
  lastPayoutAmount: 1500,
  rating: 4.6,
);

DeliveryOrder _order({
  required AssignmentStatus status,
  String orderId = 'order-1',
}) => DeliveryOrder(
  orderId: orderId,
  orderNumber: 'ORD-1001',
  assignmentStatus: status,
  totalAmount: 380,
  paymentMethod: 'COD',
  riderEarning: 52,
  estimatedDuration: 15,
  customerAddress: DeliveryAddress(name: 'Priya N', address: '12 MG Road'),
  storeAddress: DeliveryAddress(
    name: 'FreshCuts Salt Lake',
    address: 'Sector V',
  ),
  items: const <DeliveryItem>[],
);

Future<void> _pumpHome(
  WidgetTester tester, {
  required _HomeApi api,
  required ActiveDeliveryController active,
  required OnlineToggleController toggle,
  PickupSessionController? pickupSession,
}) async {
  final DeliveryRepository repository = DeliveryRepository(api);
  final FakeSocketClient socket = FakeSocketClient();
  final OffersController offers = OffersController(
    repository: repository,
    socket: socket,
  );
  final HomeDashboardController dashboard = HomeDashboardController(api: api);
  final _MockLocationService locationService = _MockLocationService();
  final _MockLocationPermissionService permissionService =
      _MockLocationPermissionService();
  when(() => permissionService.ensureWhileInUse()).thenAnswer(
    (_) async => const LocationPermissionResult(
      service: LocationServiceState.enabled,
      permission: LocationPermissionState.granted,
    ),
  );
  when(() => locationService.getCurrentPosition()).thenAnswer((_) async {
    return Position(
      latitude: 22.5726,
      longitude: 88.3639,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  });
  when(
    () => locationService.getPositionStream(any<LocationProfile>()),
  ).thenAnswer((_) => const Stream<Position>.empty());

  final LocationLifecycleManager lifecycle = LocationLifecycleManager(
    riderLocationNotifier: ValueNotifier<GeoPoint?>(null),
    locationService: locationService,
    permissionService: permissionService,
    socket: socket,
    deliveryApi: api,
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: const HomeScreen()),
      overrides: <Override>[
        homeDashboardControllerProvider.overrideWith((Ref ref) => dashboard),
        onlineToggleControllerProvider.overrideWith((Ref ref) => toggle),
        offersControllerProvider.overrideWith((Ref ref) => offers),
        activeDeliveryControllerProvider.overrideWith((Ref ref) => active),
        deliveryRepositoryProvider.overrideWithValue(repository),
        pickupSessionControllerProvider.overrideWith(
          (Ref ref) => pickupSession ?? PickupSessionController(),
        ),
        locationDisplayProvider.overrideWith(_FixedLocationDisplay.new),
        locationLifecycleManagerProvider.overrideWithValue(lifecycle),
        locationPermissionServiceProvider.overrideWithValue(permissionService),
      ],
    ),
  );

  // Let initState's post-frame dashboard refresh + provider settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  setUpAll(() {
    registerFallbackValue(LocationProfile.offline);
  });

  testWidgets('offline rider sees the offline hero with a red Go Online '
      'primary and the waiting copy', (WidgetTester tester) async {
    final _HomeApi api = _HomeApi(profile: _profile(isOnline: false));
    await _pumpHome(
      tester,
      api: api,
      active: ActiveDeliveryController(),
      toggle: OnlineToggleController(
        api: api,
        permissionService: _MockLocationPermissionService(),
        locationService: _MockLocationService(),
        isApprovedProvider: () => true,
      ),
    );

    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Go online'), findsOneWidget);
    expect(find.text("You're online"), findsNothing);
  });

  testWidgets('header greets the rider by first name and shows the '
      'assigned store line', (WidgetTester tester) async {
    final _HomeApi api = _HomeApi(profile: _profile(isOnline: false));
    await _pumpHome(
      tester,
      api: api,
      active: ActiveDeliveryController(),
      toggle: OnlineToggleController(
        api: api,
        permissionService: _MockLocationPermissionService(),
        locationService: _MockLocationService(),
        isApprovedProvider: () => true,
      ),
    );

    expect(find.text('Sayan'), findsOneWidget);
    expect(find.text('FreshCuts Store'), findsOneWidget);
    // The avatar initials fallback renders the first initial.
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('online rider sees the online hero with the location '
      'freshness line, a secondary Go Offline, and the ready-and-waiting '
      'state', (WidgetTester tester) async {
    final _HomeApi api = _HomeApi(profile: _profile(isOnline: true));
    final OnlineToggleController toggle = OnlineToggleController(
      api: api,
      permissionService: _MockLocationPermissionService(),
      locationService: _MockLocationService(),
      isApprovedProvider: () => true,
    )..syncFromProfile(isOnline: true);

    await _pumpHome(
      tester,
      api: api,
      active: ActiveDeliveryController(),
      toggle: toggle,
    );

    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text("You're online"), findsOneWidget);
    expect(find.text('Waiting for an order near your store.'), findsOneWidget);
    expect(
      find.textContaining('Bow Bazar, Kolkata'),
      findsOneWidget,
      reason: 'the location freshness line shows the reverse-geocoded area',
    );
    expect(find.text('Go offline'), findsOneWidget);
    expect(
      find.text("You're online and ready"),
      findsOneWidget,
      reason: 'idle + online shows the ready-and-waiting state',
    );
  });

  testWidgets('metrics grid renders the four real values', (
    WidgetTester tester,
  ) async {
    final _HomeApi api = _HomeApi(
      profile: _profile(isOnline: false),
      stats: _stats(),
      earnings: _earnings(),
    );
    await _pumpHome(
      tester,
      api: api,
      active: ActiveDeliveryController(),
      toggle: OnlineToggleController(
        api: api,
        permissionService: _MockLocationPermissionService(),
        locationService: _MockLocationService(),
        isApprovedProvider: () => true,
      ),
    );

    expect(find.text("Today's earnings"), findsOneWidget);
    expect(find.text('₹540'), findsOneWidget);
    expect(find.text('Delivered today'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('4.6'), findsOneWidget);
    expect(find.text('Cash in hand'), findsOneWidget);
    // The fake's default summary carries zeros — the tile renders the
    // real ledger value.
    expect(find.text('₹0'), findsOneWidget);
  });

  testWidgets('a busy online rider gets the soft-red busy hero with '
      'Continue delivery, and offers do not compete', (
    WidgetTester tester,
  ) async {
    final _HomeApi api = _HomeApi(profile: _profile(isOnline: true));
    final DeliveryOrder order = _order(status: AssignmentStatus.accepted);
    final ActiveDeliveryController active = ActiveDeliveryController()
      ..setActiveDelivery(order);
    final OnlineToggleController toggle = OnlineToggleController(
      api: api,
      permissionService: _MockLocationPermissionService(),
      locationService: _MockLocationService(),
      isApprovedProvider: () => true,
    )..syncFromProfile(isOnline: true);
    final PickupSessionController pickupSession = PickupSessionController()
      ..syncFromOrder(order);

    await _pumpHome(
      tester,
      api: api,
      active: active,
      toggle: toggle,
      pickupSession: pickupSession,
    );

    expect(find.text('1 ACTIVE DELIVERY'), findsOneWidget);
    expect(find.text('Heading to pickup'), findsOneWidget);
    expect(find.text('Pick up from FreshCuts Salt Lake'), findsOneWidget);
    expect(find.text('Continue delivery'), findsOneWidget);
    expect(find.text('Stop new orders'), findsOneWidget);
    // The active order card carries the order specifics.
    expect(find.text('Order #ORD-1001'), findsOneWidget);
    // New offers must not compete for attention while busy (§7).
    expect(find.text('NEW OFFERS'), findsNothing);
    expect(find.text("You're online and ready"), findsNothing);
  });

  testWidgets('a picked-up order flips the busy hero to in-transit', (
    WidgetTester tester,
  ) async {
    final _HomeApi api = _HomeApi(profile: _profile(isOnline: true));
    final DeliveryOrder order = _order(status: AssignmentStatus.inTransit);
    final ActiveDeliveryController active = ActiveDeliveryController()
      ..setActiveDelivery(order);
    final OnlineToggleController toggle = OnlineToggleController(
      api: api,
      permissionService: _MockLocationPermissionService(),
      locationService: _MockLocationService(),
      isApprovedProvider: () => true,
    )..syncFromProfile(isOnline: true);
    // Pickup already verified this session (socket reconcile would have
    // seeded it) — statusFor must read pickedUp for the in-transit hero.
    final PickupSessionController pickupSession = PickupSessionController()
      ..syncFromOrder(order);

    await _pumpHome(
      tester,
      api: api,
      active: active,
      toggle: toggle,
      pickupSession: pickupSession,
    );

    expect(find.text('In transit'), findsOneWidget);
    expect(find.text('Deliver to Priya N'), findsOneWidget);
  });

  testWidgets('going offline with an active delivery keeps the busy hero '
      'and says new orders are paused (§6)', (WidgetTester tester) async {
    final _HomeApi api = _HomeApi(profile: _profile(isOnline: false));
    final ActiveDeliveryController active = ActiveDeliveryController()
      ..setActiveDelivery(_order(status: AssignmentStatus.inTransit));
    // Toggle state stays offline; the delivery lifecycle outranks it.
    final OnlineToggleController toggle = OnlineToggleController(
      api: api,
      permissionService: _MockLocationPermissionService(),
      locationService: _MockLocationService(),
      isApprovedProvider: () => true,
    );

    await _pumpHome(tester, api: api, active: active, toggle: toggle);

    expect(find.text('1 ACTIVE DELIVERY'), findsOneWidget);
    expect(
      find.text('Not accepting new orders. Your active delivery continues.'),
      findsOneWidget,
    );
    // No dispatch-online secondary while offline — there is nothing to
    // stop; the rider is already not accepting new orders.
    expect(find.text('Stop new orders'), findsNothing);
    // The delivery continue action still exists — the order is live.
    expect(find.text('Continue delivery'), findsOneWidget);
  });
}
