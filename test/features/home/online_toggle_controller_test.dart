import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/core/location/location_permission_service.dart';
import 'package:meet_commerce_rider_main/core/location/location_permission_status.dart';
import 'package:meet_commerce_rider_main/core/location/location_service.dart';
import 'package:meet_commerce_rider_main/core/network/api_exception.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/home/application/online_toggle_controller.dart';

class _MockDeliveryApi extends Mock implements DeliveryApi {}

class _MockLocationPermissionService extends Mock
    implements LocationPermissionService {}

class _MockLocationService extends Mock implements LocationService {}

/// Builds a [Position] suitable for tests. The real Geolocator
/// constructor needs every field; we fill in zeros / sentinels for
/// values the controller does not read.
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

const LocationPermissionResult _serviceDisabled = LocationPermissionResult(
  service: LocationServiceState.disabled,
  permission: LocationPermissionState.granted,
);

const LocationPermissionResult _deniedOnce = LocationPermissionResult(
  service: LocationServiceState.enabled,
  permission: LocationPermissionState.deniedOnce,
);

const LocationPermissionResult _deniedForever = LocationPermissionResult(
  service: LocationServiceState.enabled,
  permission: LocationPermissionState.deniedForever,
);

void main() {
  late _MockDeliveryApi api;
  late _MockLocationPermissionService permissionService;
  late _MockLocationService locationService;

  setUpAll(() {
    // Mocktail needs a fallback for non-primitive arguments matched
    // via `any()`. We don't currently use any-matchers on these
    // types, but registering them is harmless and future-proofs.
  });

  setUp(() {
    api = _MockDeliveryApi();
    permissionService = _MockLocationPermissionService();
    locationService = _MockLocationService();
  });

  OnlineToggleController buildController({bool isApproved = true}) {
    return OnlineToggleController(
      api: api,
      permissionService: permissionService,
      locationService: locationService,
      isApprovedProvider: () => isApproved,
    );
  }

  // -------------------------------------------------------------------------
  // goOnline — permission blocked
  // -------------------------------------------------------------------------
  group('goOnline — permission blocked (R6.2/R6.3)', () {
    test(
      'denied permission sets permissionEducationNeeded and skips backend',
      () async {
        when(
          () => permissionService.ensureWhileInUse(),
        ).thenAnswer((_) async => _deniedOnce);
        final OnlineToggleController controller = buildController();

        await controller.goOnline();

        expect(controller.state.permissionEducationNeeded, isTrue);
        expect(controller.state.serviceDisabled, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.isBusy, isFalse);

        // Backend was NOT called (R6.2).
        verifyNever(() => api.toggleOnline(any<bool>()));
        verifyNever(() => api.updateLocation(any<double>(), any<double>()));
        verifyNever(() => locationService.getCurrentPosition());
      },
    );

    test('deniedForever also routes to permission education', () async {
      when(
        () => permissionService.ensureWhileInUse(),
      ).thenAnswer((_) async => _deniedForever);
      final OnlineToggleController controller = buildController();

      await controller.goOnline();

      expect(controller.state.permissionEducationNeeded, isTrue);
      verifyNever(() => api.toggleOnline(any<bool>()));
    });

    test('disabled location service surfaces serviceDisabled, not '
        'permissionEducationNeeded', () async {
      when(
        () => permissionService.ensureWhileInUse(),
      ).thenAnswer((_) async => _serviceDisabled);
      final OnlineToggleController controller = buildController();

      await controller.goOnline();

      expect(controller.state.serviceDisabled, isTrue);
      expect(controller.state.permissionEducationNeeded, isFalse);
      expect(controller.state.isOnline, isFalse);
      verifyNever(() => api.toggleOnline(any<bool>()));
    });
  });

  // -------------------------------------------------------------------------
  // goOnline — happy path
  // -------------------------------------------------------------------------
  group('goOnline — happy path (R6.4–R6.6)', () {
    test('toggles online and immediately pushes location', () async {
      when(
        () => permissionService.ensureWhileInUse(),
      ).thenAnswer((_) async => _grantedAndEnabled);
      when(
        () => locationService.getCurrentPosition(),
      ).thenAnswer((_) async => _position());
      when(() => api.toggleOnline(true)).thenAnswer((_) async {});
      when(
        () => api.updateLocation(any<double>(), any<double>()),
      ).thenAnswer((_) async {});

      final OnlineToggleController controller = buildController();
      await controller.goOnline();

      // State reflects success.
      expect(controller.state.isOnline, isTrue);
      expect(controller.state.isBusy, isFalse);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.routeToApproval, isFalse);
      expect(controller.state.permissionEducationNeeded, isFalse);
      expect(controller.state.serviceDisabled, isFalse);

      // Backend interactions happen in the documented order.
      verifyInOrder(<dynamic Function()>[
        () => permissionService.ensureWhileInUse(),
        () => locationService.getCurrentPosition(),
        () => api.toggleOnline(true),
        () => api.updateLocation(22.5726, 88.3639),
      ]);
    });

    test('a failed updateLocation does not unset isOnline', () async {
      when(
        () => permissionService.ensureWhileInUse(),
      ).thenAnswer((_) async => _grantedAndEnabled);
      when(
        () => locationService.getCurrentPosition(),
      ).thenAnswer((_) async => _position());
      when(() => api.toggleOnline(true)).thenAnswer((_) async {});
      when(
        () => api.updateLocation(any<double>(), any<double>()),
      ).thenThrow(const ApiNetworkException('offline'));

      final OnlineToggleController controller = buildController();
      await controller.goOnline();

      expect(controller.state.isOnline, isTrue);
      expect(controller.state.errorMessage, isNull);
    });

    test('null GPS fix surfaces an inline error and does NOT toggle', () async {
      when(
        () => permissionService.ensureWhileInUse(),
      ).thenAnswer((_) async => _grantedAndEnabled);
      when(
        () => locationService.getCurrentPosition(),
      ).thenAnswer((_) async => null);

      final OnlineToggleController controller = buildController();
      await controller.goOnline();

      expect(controller.state.isOnline, isFalse);
      expect(controller.state.errorMessage, isNotNull);
      verifyNever(() => api.toggleOnline(any<bool>()));
    });
  });

  // -------------------------------------------------------------------------
  // goOnline — 5xx while not approved (R6.7)
  // -------------------------------------------------------------------------
  group('goOnline — 5xx while not approved routes to approval', () {
    test('ApiServerException + !isApproved => routeToApproval=true', () async {
      when(
        () => permissionService.ensureWhileInUse(),
      ).thenAnswer((_) async => _grantedAndEnabled);
      when(
        () => locationService.getCurrentPosition(),
      ).thenAnswer((_) async => _position());
      when(() => api.toggleOnline(true)).thenThrow(
        const ApiServerException(
          'Internal server error',
          statusCode: 500,
          backendCode: 'INTERNAL_ERROR',
        ),
      );

      final OnlineToggleController controller = buildController(
        isApproved: false,
      );
      await controller.goOnline();

      expect(controller.state.routeToApproval, isTrue);
      expect(controller.state.isOnline, isFalse);
      expect(controller.state.isBusy, isFalse);

      // updateLocation is never called when toggle fails.
      verifyNever(() => api.updateLocation(any<double>(), any<double>()));
    });

    test(
      'ApiServerException + isApproved => surface inline error, no route',
      () async {
        when(
          () => permissionService.ensureWhileInUse(),
        ).thenAnswer((_) async => _grantedAndEnabled);
        when(
          () => locationService.getCurrentPosition(),
        ).thenAnswer((_) async => _position());
        when(() => api.toggleOnline(true)).thenThrow(
          const ApiServerException(
            'Internal server error',
            statusCode: 500,
            backendCode: 'INTERNAL_ERROR',
          ),
        );

        final OnlineToggleController controller = buildController(
          isApproved: true,
        );
        await controller.goOnline();

        expect(controller.state.routeToApproval, isFalse);
        expect(controller.state.errorMessage, isNotNull);
        expect(controller.state.isOnline, isFalse);
      },
    );

    test('typed RiderNotApprovedError always routes to approval', () async {
      when(
        () => permissionService.ensureWhileInUse(),
      ).thenAnswer((_) async => _grantedAndEnabled);
      when(
        () => locationService.getCurrentPosition(),
      ).thenAnswer((_) async => _position());
      when(
        () => api.toggleOnline(true),
      ).thenThrow(const RiderNotApprovedError());

      // Even when isApproved reports true, the typed error wins.
      final OnlineToggleController controller = buildController(
        isApproved: true,
      );
      await controller.goOnline();

      expect(controller.state.routeToApproval, isTrue);
      expect(controller.state.isOnline, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // goOffline
  // -------------------------------------------------------------------------
  group('goOffline', () {
    test('calls toggleOnline(false) and resets isOnline', () async {
      when(() => api.toggleOnline(false)).thenAnswer((_) async {});

      final OnlineToggleController controller = buildController();
      // Simulate the controller being online before going offline.
      controller.syncFromProfile(isOnline: true);
      expect(controller.state.isOnline, isTrue);

      await controller.goOffline();

      expect(controller.state.isOnline, isFalse);
      expect(controller.state.isBusy, isFalse);
      expect(controller.state.errorMessage, isNull);
      verify(() => api.toggleOnline(false)).called(1);
    });

    test('forces isOnline to false even when backend errors', () async {
      when(
        () => api.toggleOnline(false),
      ).thenThrow(const ApiNetworkException('offline'));

      final OnlineToggleController controller = buildController();
      controller.syncFromProfile(isOnline: true);

      await controller.goOffline();

      expect(controller.state.isOnline, isFalse);
      expect(controller.state.errorMessage, isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // goOnline — suspension gate (Big Phase 6)
  // -------------------------------------------------------------------------
  group('goOnline — suspension gate', () {
    test(
      'typed RiderSuspendedError sets accountSuspended and never routes to approval',
      () async {
        when(
          () => permissionService.ensureWhileInUse(),
        ).thenAnswer((_) async => _grantedAndEnabled);
        when(
          () => locationService.getCurrentPosition(),
        ).thenAnswer((_) async => _position());
        when(
          () => api.toggleOnline(true),
        ).thenThrow(const RiderSuspendedError());

        final OnlineToggleController controller = buildController(
          isApproved: true,
        );
        await controller.goOnline();

        expect(controller.state.accountSuspended, isTrue);
        expect(controller.state.routeToApproval, isFalse);
        expect(controller.state.isOnline, isFalse);
        expect(controller.state.isBusy, isFalse);
        expect(controller.state.errorMessage, isNull);
      },
    );

    test(
      'a 403 auth failure WITHOUT a typed suspension code stays a plain error',
      () async {
        when(
          () => permissionService.ensureWhileInUse(),
        ).thenAnswer((_) async => _grantedAndEnabled);
        when(
          () => locationService.getCurrentPosition(),
        ).thenAnswer((_) async => _position());
        when(() => api.toggleOnline(true)).thenThrow(
          const ApiAuthException(
            'Forbidden',
            statusCode: 403,
            backendCode: 'SOMETHING_ELSE',
          ),
        );

        final OnlineToggleController controller = buildController();
        await controller.goOnline();

        expect(controller.state.accountSuspended, isFalse);
        expect(controller.state.routeToApproval, isFalse);
        expect(controller.state.errorMessage, isNotNull);
      },
    );

    test('clearTransientFlags also wipes accountSuspended', () async {
      when(
        () => permissionService.ensureWhileInUse(),
      ).thenAnswer((_) async => _grantedAndEnabled);
      when(
        () => locationService.getCurrentPosition(),
      ).thenAnswer((_) async => _position());
      when(() => api.toggleOnline(true)).thenThrow(const RiderSuspendedError());

      final OnlineToggleController controller = buildController();
      await controller.goOnline();
      expect(controller.state.accountSuspended, isTrue);

      controller.clearTransientFlags();
      expect(controller.state.accountSuspended, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // syncFromProfile / clearTransientFlags
  // -------------------------------------------------------------------------
  group('state helpers', () {
    test('syncFromProfile mirrors the backend flag', () {
      final OnlineToggleController controller = buildController();
      controller.syncFromProfile(isOnline: true);
      expect(controller.state.isOnline, isTrue);
      controller.syncFromProfile(isOnline: false);
      expect(controller.state.isOnline, isFalse);
    });

    test('clearTransientFlags wipes one-shot signals', () async {
      when(
        () => permissionService.ensureWhileInUse(),
      ).thenAnswer((_) async => _deniedOnce);
      final OnlineToggleController controller = buildController();
      await controller.goOnline();
      expect(controller.state.permissionEducationNeeded, isTrue);

      controller.clearTransientFlags();
      expect(controller.state.permissionEducationNeeded, isFalse);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.serviceDisabled, isFalse);
      expect(controller.state.routeToApproval, isFalse);
    });
  });
}
