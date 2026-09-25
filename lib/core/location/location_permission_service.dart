import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../utils/app_logger.dart';
import 'location_permission_status.dart';

/// Thin transport seam between [LocationPermissionService] and the
/// underlying `geolocator` / `permission_handler` plugins.
///
/// Defined as an `abstract interface class` so unit tests can supply a
/// hand-rolled test double without a platform-channel binding (Geolocator's
/// static methods are unmockable). The single production implementation
/// [_GeolocatorPermissionPort] simply forwards each call.
///
/// Each method intentionally returns the raw plugin types rather than the
/// project enums so the translation logic stays in
/// [LocationPermissionService] where it can be unit-tested as a pure
/// function over the port outputs.
abstract interface class LocationPermissionPort {
  /// `Geolocator.isLocationServiceEnabled()`.
  Future<bool> isLocationServiceEnabled();

  /// `Geolocator.checkPermission()`.
  Future<LocationPermission> checkPermission();

  /// `Geolocator.requestPermission()`.
  Future<LocationPermission> requestPermission();

  /// `permission_handler.openAppSettings()`.
  Future<bool> openAppSettings();

  /// `Geolocator.openLocationSettings()`.
  Future<bool> openLocationSettings();
}

/// Production [LocationPermissionPort] backed by the real plugins.
///
/// Kept private so callers can only reach it via the
/// [LocationPermissionService] default constructor.
class _GeolocatorPermissionPort implements LocationPermissionPort {
  const _GeolocatorPermissionPort();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

/// Concrete location-permission gate used by the online toggle.
///
/// Wraps a [LocationPermissionPort] so the production class talks to the
/// real `geolocator` and `permission_handler` plugins, while unit tests
/// can inject a hand-rolled port that returns canned states without a
/// platform binding.
///
/// Methods:
///
/// - [check] — read-only snapshot, never prompts.
/// - [ensureWhileInUse] — full flow: checks service state, prompts for
///   permission once when `denied`, and returns the final
///   [LocationPermissionResult]. The caller is responsible for routing
///   the user to the permission education screen or settings page based
///   on the resulting state.
/// - [openAppSettings] — opens the app settings page so a permanently
///   denied permission can be re-granted (R29.2).
/// - [openLocationSettings] — opens the OS location-services settings
///   page so disabled services can be re-enabled (R6.2 / R29.2).
///
/// Logging:
/// Every state transition observed during [ensureWhileInUse] is logged at
/// `info` level via [AppLogger] under [LogTopic.location] so the rider's
/// permission journey is reproducible from device logs.
///
/// Requirements traced: R6.1–R6.4, R29.1–R29.3.
class LocationPermissionService {
  /// Production constructor: wires to the real Geolocator /
  /// permission_handler plugins.
  LocationPermissionService() : _port = const _GeolocatorPermissionPort();

  /// Test constructor: accepts a custom [LocationPermissionPort].
  ///
  /// Used by `test/core/location/location_permission_service_test.dart`
  /// to drive the service through arbitrary plugin states without a
  /// platform-channel binding.
  LocationPermissionService.withPort(LocationPermissionPort port)
    : _port = port;

  final LocationPermissionPort _port;

  // ---------------------------------------------------------------------------
  // Read-only check
  // ---------------------------------------------------------------------------

  /// Returns the current permission and service state without prompting.
  ///
  /// Used at app startup and whenever the UI needs to render the current
  /// permission posture (e.g., the online-toggle pill) without surfacing
  /// an OS dialog.
  Future<LocationPermissionResult> check() async {
    final bool serviceEnabled = await _port.isLocationServiceEnabled();
    final LocationPermission raw = await _port.checkPermission();
    final LocationPermissionResult result = LocationPermissionResult(
      service: _mapService(serviceEnabled),
      permission: _mapPermission(raw),
    );
    AppLogger.info(
      LogTopic.location,
      'check() -> service=${result.service.name}, '
      'permission=${result.permission.name}',
    );
    return result;
  }

  // ---------------------------------------------------------------------------
  // Full ensure flow
  // ---------------------------------------------------------------------------

  /// Resolves the rider's permission state, prompting once if needed.
  ///
  /// Flow:
  ///
  /// 1. If location services are disabled, return immediately with
  ///    [LocationServiceState.disabled] and the current permission state
  ///    (no prompt — turning services back on is the user's job).
  /// 2. Read the current permission state via the port.
  /// 3. If it's [LocationPermissionState.deniedOnce], call
  ///    `requestPermission()` once and use the resulting state.
  /// 4. For any other state ([granted], [deniedForever], or
  ///    [restricted]) skip the prompt and return the read-only state —
  ///    a prompt would either be redundant ([granted]) or a no-op
  ///    ([deniedForever] / [restricted]).
  ///
  /// Logs each meaningful transition at `info` level.
  Future<LocationPermissionResult> ensureWhileInUse() async {
    final bool serviceEnabled = await _port.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Still surface the current permission state so the UI can
      // summarise both blockers at once if it wants to.
      final LocationPermission raw = await _port.checkPermission();
      final LocationPermissionResult result = LocationPermissionResult(
        service: LocationServiceState.disabled,
        permission: _mapPermission(raw),
      );
      AppLogger.info(
        LogTopic.location,
        'ensureWhileInUse() -> service disabled '
        '(permission=${result.permission.name})',
      );
      return result;
    }

    final LocationPermission initialRaw = await _port.checkPermission();
    final LocationPermissionState initial = _mapPermission(initialRaw);

    LocationPermissionState finalState = initial;
    if (initial == LocationPermissionState.deniedOnce) {
      AppLogger.info(
        LogTopic.location,
        'ensureWhileInUse() prompting (initial=deniedOnce)',
      );
      final LocationPermission afterPromptRaw = await _port.requestPermission();
      finalState = _mapPermission(afterPromptRaw);
      AppLogger.info(
        LogTopic.location,
        'ensureWhileInUse() prompt result -> ${finalState.name}',
      );
    } else {
      AppLogger.info(
        LogTopic.location,
        'ensureWhileInUse() skipping prompt (state=${initial.name})',
      );
    }

    return LocationPermissionResult(
      service: LocationServiceState.enabled,
      permission: finalState,
    );
  }

  // ---------------------------------------------------------------------------
  // Settings affordances
  // ---------------------------------------------------------------------------

  /// Opens the app's settings page so the rider can re-enable a
  /// permanently denied permission (R29.2).
  ///
  /// Returns `true` when the page opened. Failures are logged but not
  /// thrown so the caller can simply guard the UI behind the boolean.
  Future<bool> openAppSettings() async {
    final bool opened = await _port.openAppSettings();
    AppLogger.info(LogTopic.location, 'openAppSettings() -> opened=$opened');
    return opened;
  }

  /// Opens the system location-services settings page so the rider can
  /// re-enable services (R6.2 / R29.2).
  ///
  /// Returns `true` when the page opened.
  Future<bool> openLocationSettings() async {
    final bool opened = await _port.openLocationSettings();
    AppLogger.info(
      LogTopic.location,
      'openLocationSettings() -> opened=$opened',
    );
    return opened;
  }

  // ---------------------------------------------------------------------------
  // Translation helpers
  // ---------------------------------------------------------------------------

  /// Maps a `bool` from `Geolocator.isLocationServiceEnabled()` to the
  /// project enum.
  static LocationServiceState _mapService(bool enabled) {
    return enabled
        ? LocationServiceState.enabled
        : LocationServiceState.disabled;
  }

  /// Maps Geolocator's [LocationPermission] enum onto the project
  /// [LocationPermissionState].
  ///
  /// `unableToDetermine` is treated as [LocationPermissionState.deniedOnce]
  /// because the safe answer is to prompt the user once: if the OS
  /// rejects the prompt the result will surface as `deniedOnce` again
  /// and the UI will route to the education screen.
  static LocationPermissionState _mapPermission(LocationPermission raw) {
    switch (raw) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.denied:
        return LocationPermissionState.deniedOnce;
      case LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.deniedOnce;
    }
  }
}
