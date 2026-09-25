import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/core/location/location_permission_service.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_status.dart';

// ---------------------------------------------------------------------------
// Mocktail double for [LocationPermissionPort].
//
// Geolocator exposes its API as static methods, so mocktail can't mock the
// plugin directly. Instead we inject a stand-in [LocationPermissionPort]
// and stub its (instance) methods with mocktail. The
// [LocationPermissionService.withPort] constructor exists for exactly
// this use case.
// ---------------------------------------------------------------------------

class _MockPort extends Mock implements LocationPermissionPort {}

void main() {
  // Mocktail does not register fallbacks for the plugin enums; we never
  // need one because every stub returns a concrete value.

  group('LocationPermissionService.check', () {
    test(
      'returns LocationServiceState.disabled when location services are off',
      () async {
        final _MockPort port = _MockPort();
        when(port.isLocationServiceEnabled).thenAnswer((_) async => false);
        when(
          port.checkPermission,
        ).thenAnswer((_) async => LocationPermission.whileInUse);
        final LocationPermissionService service =
            LocationPermissionService.withPort(port);

        final LocationPermissionResult result = await service.check();

        expect(result.service, LocationServiceState.disabled);
        expect(result.permission, LocationPermissionState.granted);
        expect(result.canUseLocation, isFalse);
        // Read-only check must NEVER prompt.
        verifyNever(port.requestPermission);
      },
    );

    test(
      'returns granted when service is enabled and permission is whileInUse',
      () async {
        final _MockPort port = _MockPort();
        when(port.isLocationServiceEnabled).thenAnswer((_) async => true);
        when(
          port.checkPermission,
        ).thenAnswer((_) async => LocationPermission.whileInUse);
        final LocationPermissionService service =
            LocationPermissionService.withPort(port);

        final LocationPermissionResult result = await service.check();

        expect(result.service, LocationServiceState.enabled);
        expect(result.permission, LocationPermissionState.granted);
        expect(result.canUseLocation, isTrue);
        verifyNever(port.requestPermission);
      },
    );

    test('maps deniedForever through without prompting', () async {
      final _MockPort port = _MockPort();
      when(port.isLocationServiceEnabled).thenAnswer((_) async => true);
      when(
        port.checkPermission,
      ).thenAnswer((_) async => LocationPermission.deniedForever);
      final LocationPermissionService service =
          LocationPermissionService.withPort(port);

      final LocationPermissionResult result = await service.check();

      expect(result.service, LocationServiceState.enabled);
      expect(result.permission, LocationPermissionState.deniedForever);
      expect(result.canUseLocation, isFalse);
      verifyNever(port.requestPermission);
    });
  });

  group('LocationPermissionService.ensureWhileInUse', () {
    test('returns disabled when service is off and does not prompt', () async {
      final _MockPort port = _MockPort();
      when(port.isLocationServiceEnabled).thenAnswer((_) async => false);
      when(
        port.checkPermission,
      ).thenAnswer((_) async => LocationPermission.denied);
      final LocationPermissionService service =
          LocationPermissionService.withPort(port);

      final LocationPermissionResult result = await service.ensureWhileInUse();

      expect(result.service, LocationServiceState.disabled);
      expect(result.permission, LocationPermissionState.deniedOnce);
      expect(result.canUseLocation, isFalse);
      verifyNever(port.requestPermission);
    });

    test('transitions deniedOnce -> granted via requestPermission', () async {
      final _MockPort port = _MockPort();
      when(port.isLocationServiceEnabled).thenAnswer((_) async => true);
      when(
        port.checkPermission,
      ).thenAnswer((_) async => LocationPermission.denied);
      when(
        port.requestPermission,
      ).thenAnswer((_) async => LocationPermission.whileInUse);
      final LocationPermissionService service =
          LocationPermissionService.withPort(port);

      final LocationPermissionResult result = await service.ensureWhileInUse();

      expect(result.service, LocationServiceState.enabled);
      expect(result.permission, LocationPermissionState.granted);
      expect(result.canUseLocation, isTrue);
      verify(port.requestPermission).called(1);
    });

    test(
      'transitions deniedOnce -> deniedForever surfaces correctly',
      () async {
        final _MockPort port = _MockPort();
        when(port.isLocationServiceEnabled).thenAnswer((_) async => true);
        when(
          port.checkPermission,
        ).thenAnswer((_) async => LocationPermission.denied);
        when(
          port.requestPermission,
        ).thenAnswer((_) async => LocationPermission.deniedForever);
        final LocationPermissionService service =
            LocationPermissionService.withPort(port);

        final LocationPermissionResult result = await service
            .ensureWhileInUse();

        expect(result.service, LocationServiceState.enabled);
        expect(result.permission, LocationPermissionState.deniedForever);
        expect(result.canUseLocation, isFalse);
        verify(port.requestPermission).called(1);
      },
    );

    test('does not prompt when permission is already granted', () async {
      final _MockPort port = _MockPort();
      when(port.isLocationServiceEnabled).thenAnswer((_) async => true);
      when(
        port.checkPermission,
      ).thenAnswer((_) async => LocationPermission.always);
      final LocationPermissionService service =
          LocationPermissionService.withPort(port);

      final LocationPermissionResult result = await service.ensureWhileInUse();

      expect(result.permission, LocationPermissionState.granted);
      expect(result.canUseLocation, isTrue);
      verifyNever(port.requestPermission);
    });

    test('does not prompt when permission is deniedForever', () async {
      final _MockPort port = _MockPort();
      when(port.isLocationServiceEnabled).thenAnswer((_) async => true);
      when(
        port.checkPermission,
      ).thenAnswer((_) async => LocationPermission.deniedForever);
      final LocationPermissionService service =
          LocationPermissionService.withPort(port);

      final LocationPermissionResult result = await service.ensureWhileInUse();

      expect(result.service, LocationServiceState.enabled);
      expect(result.permission, LocationPermissionState.deniedForever);
      verifyNever(port.requestPermission);
    });

    test(
      'prompts only once when initial state is deniedOnce and user denies again',
      () async {
        final _MockPort port = _MockPort();
        when(port.isLocationServiceEnabled).thenAnswer((_) async => true);
        when(
          port.checkPermission,
        ).thenAnswer((_) async => LocationPermission.denied);
        when(
          port.requestPermission,
        ).thenAnswer((_) async => LocationPermission.denied);
        final LocationPermissionService service =
            LocationPermissionService.withPort(port);

        final LocationPermissionResult result = await service
            .ensureWhileInUse();

        expect(result.permission, LocationPermissionState.deniedOnce);
        expect(result.canUseLocation, isFalse);
        verify(port.requestPermission).called(1);
      },
    );
  });

  group('LocationPermissionService settings affordances', () {
    test('openAppSettings forwards to the port', () async {
      final _MockPort port = _MockPort();
      when(port.openAppSettings).thenAnswer((_) async => true);
      final LocationPermissionService service =
          LocationPermissionService.withPort(port);

      final bool opened = await service.openAppSettings();

      expect(opened, isTrue);
      verify(port.openAppSettings).called(1);
    });

    test('openLocationSettings forwards to the port', () async {
      final _MockPort port = _MockPort();
      when(port.openLocationSettings).thenAnswer((_) async => true);
      final LocationPermissionService service =
          LocationPermissionService.withPort(port);

      final bool opened = await service.openLocationSettings();

      expect(opened, isTrue);
      verify(port.openLocationSettings).called(1);
    });
  });

  group('LocationPermissionResult.canUseLocation', () {
    test('true only when service.enabled and permission.granted', () {
      const LocationPermissionResult ok = LocationPermissionResult(
        service: LocationServiceState.enabled,
        permission: LocationPermissionState.granted,
      );
      expect(ok.canUseLocation, isTrue);
    });

    test('false when service.disabled even if permission.granted', () {
      const LocationPermissionResult disabledService = LocationPermissionResult(
        service: LocationServiceState.disabled,
        permission: LocationPermissionState.granted,
      );
      expect(disabledService.canUseLocation, isFalse);
    });

    test('false for any non-granted permission', () {
      const List<LocationPermissionState> nonGranted =
          <LocationPermissionState>[
            LocationPermissionState.deniedOnce,
            LocationPermissionState.deniedForever,
            LocationPermissionState.restricted,
          ];
      for (final LocationPermissionState p in nonGranted) {
        final LocationPermissionResult r = LocationPermissionResult(
          service: LocationServiceState.enabled,
          permission: p,
        );
        expect(
          r.canUseLocation,
          isFalse,
          reason: 'expected canUseLocation == false for permission=$p',
        );
      }
    });
  });
}
