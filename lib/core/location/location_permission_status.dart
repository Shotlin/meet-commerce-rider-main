/// Project-level enums and result type for location permission state.
///
/// These types are pure Dart with no Flutter or platform-channel
/// dependencies so the permission flow can be unit-tested without a
/// platform binding. The concrete [LocationPermissionService] in
/// `location_permission_service.dart` translates between the underlying
/// `geolocator` enums and the project enums declared here.
///
/// Requirements traced: R6.1–R6.4, R29.1–R29.3.
library;

/// Whether the device's location services (the OS-level GPS toggle) are
/// turned on.
///
/// Distinct from [LocationPermissionState]: a rider can have a granted
/// permission while location services are still disabled, and vice
/// versa. The R6.2 / R29.2 flow needs both signals.
enum LocationServiceState {
  /// Location services are turned on.
  enabled,

  /// Location services are turned off; the user must open the OS
  /// location-services settings page to enable them.
  disabled,
}

/// Project-level location permission state, mapped from the underlying
/// plugin's enum.
///
/// We deliberately collapse `whileInUse` and `always` into [granted]:
/// the rider app only needs whileInUse for foreground tracking
/// (R29.3), so the distinction is irrelevant to the gating logic.
enum LocationPermissionState {
  /// Permission is granted (whileInUse or always); the app may use
  /// location.
  granted,

  /// Permission was denied by the user but the OS still allows another
  /// prompt. Gates the "request once" branch in R6.3 / R29.1.
  deniedOnce,

  /// Permission was permanently denied; another prompt would no-op and
  /// the user must open the app settings page to re-enable it
  /// (R29.2).
  deniedForever,

  /// Permission is restricted by parental controls or device policy
  /// and cannot be changed by the user.
  restricted,
}

/// Combined snapshot of [LocationServiceState] and
/// [LocationPermissionState].
///
/// Returned by every method on [LocationPermissionService] that produces
/// a permission outcome. Callers branch on [canUseLocation] for the
/// happy path and inspect [service] / [permission] separately to drive
/// the UI for the failure paths (services off vs. denied vs.
/// permanently denied vs. restricted).
class LocationPermissionResult {
  /// Constructs a snapshot.
  const LocationPermissionResult({
    required this.service,
    required this.permission,
  });

  /// Device-level location services state.
  final LocationServiceState service;

  /// App-level permission state.
  final LocationPermissionState permission;

  /// Convenience: `true` iff location services are on AND permission
  /// has been granted. The rider may go online when this is `true`.
  ///
  /// We deliberately do NOT check [LocationPermissionState.restricted]
  /// or [LocationPermissionState.deniedForever] here: the only state
  /// that yields `canUseLocation == true` is the explicit
  /// [LocationPermissionState.granted] paired with
  /// [LocationServiceState.enabled].
  bool get canUseLocation =>
      service == LocationServiceState.enabled &&
      permission == LocationPermissionState.granted;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationPermissionResult &&
        other.service == service &&
        other.permission == permission;
  }

  @override
  int get hashCode => Object.hash(service, permission);

  @override
  String toString() =>
      'LocationPermissionResult(service: $service, permission: $permission)';
}
