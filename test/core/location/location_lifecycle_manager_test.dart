import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/core/location/location_lifecycle_manager.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_service.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_status.dart';
import 'package:meet_commerce_rider_main/core/location/location_profile.dart';
import 'package:meet_commerce_rider_main/core/location/location_service.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/realtime/socket_client.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';

class _MockLocationService extends Mock implements LocationService {}

class _MockLocationPermissionService extends Mock
    implements LocationPermissionService {}

class _MockSocketClient extends Mock implements SocketClient {}

class _MockDeliveryApi extends Mock implements DeliveryApi {}

Position _position({double latitude = 22.5726, double longitude = 88.3639}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

const LocationPermissionResult _grantedAndEnabled = LocationPermissionResult(
  service: LocationServiceState.enabled,
  permission: LocationPermissionState.granted,
);

void main() {
  late _MockLocationService locationService;
  late _MockLocationPermissionService permissionService;
  late _MockSocketClient socket;
  late _MockDeliveryApi deliveryApi;
  late ValueNotifier<GeoPoint?> markerNotifier;

  /// Profiles requested from [LocationService.getPositionStream], in
  /// order — the observable proxy for "which profile is streaming".
  final List<LocationProfile> requestedProfiles = <LocationProfile>[];

  setUpAll(() {
    registerFallbackValue(LocationProfile.offline);
  });

  setUp(() {
    locationService = _MockLocationService();
    permissionService = _MockLocationPermissionService();
    socket = _MockSocketClient();
    deliveryApi = _MockDeliveryApi();
    markerNotifier = ValueNotifier<GeoPoint?>(null);
    requestedProfiles.clear();
    when(
      () => permissionService.ensureWhileInUse(),
    ).thenAnswer((_) async => _grantedAndEnabled);
    when(
      () => locationService.getCurrentPosition(),
    ).thenAnswer((_) async => _position());
    when(() => socket.status).thenReturn(SocketStatus.disconnected);
    when(() => socket.emit(any(), any())).thenReturn(null);
    when(
      () => deliveryApi.updateLocation(any<double>(), any<double>()),
    ).thenAnswer((_) async {});
    when(
      () => locationService.getPositionStream(any<LocationProfile>()),
    ).thenAnswer((Invocation invocation) {
      requestedProfiles.add(
        invocation.positionalArguments.single as LocationProfile,
      );
      // A completed stream: the manager keeps the subscription object
      // (isStreaming == true) and a later _startStream can cancel it
      // without hanging. Tests drive _publish via the seed fix only.
      return Stream<Position>.empty();
    });
  });

  LocationLifecycleManager buildManager() => LocationLifecycleManager(
    riderLocationNotifier: markerNotifier,
    locationService: locationService,
    permissionService: permissionService,
    socket: socket,
    deliveryApi: deliveryApi,
  );

  group('offline during an active delivery (blueprint §6)', () {
    test(
      'onWentOfflineDuringDelivery keeps streaming on the heading-to-store profile',
      () async {
        final LocationLifecycleManager manager = buildManager();
        await manager.onWentOnline();
        expect(manager.isStreaming, isTrue);

        await manager.onWentOfflineDuringDelivery(pickedUp: false);

        // Tracking must NOT stop: the stream is still running and was
        // (re)requested with the active-delivery profile.
        expect(manager.isStreaming, isTrue);
        expect(requestedProfiles.last, LocationProfile.acceptedToStore);
      },
    );

    test(
      'pickedUp=true switches to the in-transit profile without stopping',
      () async {
        final LocationLifecycleManager manager = buildManager();
        await manager.onWentOnline();
        requestedProfiles.clear();

        await manager.onWentOfflineDuringDelivery(pickedUp: true);

        expect(manager.isStreaming, isTrue);
        expect(requestedProfiles.single, LocationProfile.inTransitToCustomer);
      },
    );

    test(
      'no profile restart when the matching profile is already streaming',
      () async {
        final LocationLifecycleManager manager = buildManager();
        await manager.onWentOnline();
        await manager.onAcceptedOrder();
        requestedProfiles.clear();

        await manager.onWentOfflineDuringDelivery(pickedUp: false);

        // Same profile → no new stream request, the existing one keeps
        // running (a restart would drop fixes mid-navigation).
        expect(requestedProfiles, isEmpty);
        expect(manager.isStreaming, isTrue);
      },
    );

    test(
      'onWentOffline still stops streaming when no delivery is active',
      () async {
        final LocationLifecycleManager manager = buildManager();
        await manager.onWentOnline();

        await manager.onWentOffline();

        expect(manager.isStreaming, isFalse);
      },
    );

    test(
      'after offline-during-delivery, delivery end returns to waiting-online streaming',
      () async {
        final LocationLifecycleManager manager = buildManager();
        await manager.onWentOnline();
        await manager.onWentOfflineDuringDelivery(pickedUp: true);

        await manager.onDeliveryEnded();

        // The rider is dispatch-offline now, but tracking continues on
        // the waiting profile — the stream never stops.
        expect(manager.isStreaming, isTrue);
        expect(requestedProfiles.last, LocationProfile.waitingOnline);
      },
    );
  });

  group('ensureRunningIfOnline with active delivery restore', () {
    test(
      'starts streaming for an offline rider with an active delivery',
      () async {
        final LocationLifecycleManager manager = buildManager();

        final bool started = await manager.ensureRunningIfOnline(
          isOnline: false,
          hasActiveDelivery: true,
        );

        expect(started, isTrue);
        expect(manager.isStreaming, isTrue);
        expect(requestedProfiles.last, LocationProfile.waitingOnline);
      },
    );

    test('stays stopped for an offline rider without a delivery', () async {
      final LocationLifecycleManager manager = buildManager();

      final bool started = await manager.ensureRunningIfOnline(
        isOnline: false,
        hasActiveDelivery: false,
      );

      expect(started, isFalse);
      expect(manager.isStreaming, isFalse);
      verifyNever(() => locationService.getPositionStream(any()));
    });

    test('does not double-start when already streaming', () async {
      final LocationLifecycleManager manager = buildManager();
      await manager.onWentOnline();
      requestedProfiles.clear();

      final bool started = await manager.ensureRunningIfOnline(
        isOnline: true,
        hasActiveDelivery: true,
      );

      expect(started, isTrue);
      expect(requestedProfiles, isEmpty);
    });
  });

  group('seed + upload plumbing (regression guard for the offline path)', () {
    test(
      'a seeded fix reaches the marker notifier and the REST fallback',
      () async {
        final LocationLifecycleManager manager = buildManager();
        await manager.ensureRunningIfOnline(
          isOnline: false,
          hasActiveDelivery: true,
        );

        expect(markerNotifier.value, isNotNull);
        expect(markerNotifier.value!.latitude, 22.5726);

        // Socket is disconnected in this test → REST fallback used.
        await untilCalled(
          () => deliveryApi.updateLocation(any<double>(), any<double>()),
        );
        verify(() => deliveryApi.updateLocation(22.5726, 88.3639)).called(1);
      },
    );
  });
}
