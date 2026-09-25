import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:meet_commerce_rider_main/core/location/delivery_location_phase_sync.dart';
import 'package:meet_commerce_rider_main/core/location/location_lifecycle_manager.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_service.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_status.dart';
import 'package:meet_commerce_rider_main/core/location/location_profile.dart';
import 'package:meet_commerce_rider_main/core/location/location_service.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/features/delivery/application/active_delivery_map_controller.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';

import '../../helpers/fake_delivery_api.dart';
import '../../helpers/fake_socket_client.dart';

class _MockLocationService extends Mock implements LocationService {}

class _MockLocationPermissionService extends Mock
    implements LocationPermissionService {}

/// The profiles requested from the (stubbed) GPS stream, in order —
/// the observable proxy for "which profile is active".
List<LocationProfile> requestedProfilesOf(
  List<LocationProfile> sink,
  LocationService service,
) => sink;

void main() {
  setUpAll(() {
    registerFallbackValue(LocationProfile.offline);
  });

  late _MockLocationService locationService;
  late _MockLocationPermissionService permissionService;
  final List<LocationProfile> requestedProfiles = <LocationProfile>[];

  setUp(() {
    locationService = _MockLocationService();
    permissionService = _MockLocationPermissionService();
    requestedProfiles.clear();

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
    ).thenAnswer((Invocation invocation) {
      requestedProfiles.add(
        invocation.positionalArguments.single as LocationProfile,
      );
      return const Stream<Position>.empty();
    });
  });

  LocationLifecycleManager buildManager() => LocationLifecycleManager(
    riderLocationNotifier: ValueNotifier<GeoPoint?>(null),
    locationService: locationService,
    permissionService: permissionService,
    socket: FakeSocketClient(),
    deliveryApi: FakeDeliveryApi(),
  );

  test('toStore escalates the profile to accepted-to-store', () async {
    final LocationLifecycleManager manager = buildManager();
    await manager.onWentOnline();
    requestedProfiles.clear();

    final DeliveryLocationPhaseSync sync = DeliveryLocationPhaseSync();
    expect(await sync.apply(LocationPhase.toStore, manager), isTrue);
    await pumpEventQueue();
    expect(requestedProfiles.last, LocationProfile.acceptedToStore);
    expect(sync.lastPhase, LocationPhase.toStore);
  });

  test('toCustomer escalates further to in-transit', () async {
    final LocationLifecycleManager manager = buildManager();
    await manager.onWentOnline();
    final DeliveryLocationPhaseSync sync = DeliveryLocationPhaseSync();
    await sync.apply(LocationPhase.toStore, manager);
    requestedProfiles.clear();

    expect(await sync.apply(LocationPhase.toCustomer, manager), isTrue);
    await pumpEventQueue();
    expect(requestedProfiles.last, LocationProfile.inTransitToCustomer);
  });

  test('none after an active phase returns to waiting-online without '
      'stopping the stream', () async {
    final LocationLifecycleManager manager = buildManager();
    await manager.onWentOnline();
    final DeliveryLocationPhaseSync sync = DeliveryLocationPhaseSync();
    await sync.apply(LocationPhase.toCustomer, manager);
    requestedProfiles.clear();

    expect(await sync.apply(LocationPhase.none, manager), isTrue);
    await pumpEventQueue();
    expect(requestedProfiles.last, LocationProfile.waitingOnline);
  });

  test('none as the FIRST phase is a no-op (fresh screen, no delivery '
      'ever started)', () async {
    final LocationLifecycleManager manager = buildManager();
    await manager.onWentOnline();
    requestedProfiles.clear();

    final DeliveryLocationPhaseSync sync = DeliveryLocationPhaseSync();
    expect(await sync.apply(LocationPhase.none, manager), isTrue);
    expect(requestedProfiles, isEmpty, reason: 'no lifecycle call made');
  });

  test('repeated phases are deduplicated', () async {
    final LocationLifecycleManager manager = buildManager();
    await manager.onWentOnline();
    final DeliveryLocationPhaseSync sync = DeliveryLocationPhaseSync();
    await sync.apply(LocationPhase.toStore, manager);
    requestedProfiles.clear();

    expect(await sync.apply(LocationPhase.toStore, manager), isFalse);
    await pumpEventQueue();
    expect(requestedProfiles, isEmpty);
  });

  test('reset clears the last phase', () async {
    final DeliveryLocationPhaseSync sync = DeliveryLocationPhaseSync();
    final LocationLifecycleManager manager = buildManager();
    await sync.apply(LocationPhase.toStore, manager);
    sync.reset();
    expect(sync.lastPhase, isNull);
    // After a reset, none no longer means "delivery ended".
    requestedProfiles.clear();
    expect(await sync.apply(LocationPhase.none, manager), isTrue);
    expect(requestedProfiles, isEmpty);
  });
}
