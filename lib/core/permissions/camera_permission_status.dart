/// Project-level enum for camera permission state.
///
/// Mirrors `location_permission_status.dart`'s
/// [LocationPermissionState] shape (minus the location-services-on/off
/// distinction, which has no camera equivalent) so
/// [CameraPermissionService] follows the same translation-layer pattern
/// as [LocationPermissionService].
library;

enum CameraPermissionState {
  /// Permission is granted; the QR scanner may open the camera.
  granted,

  /// Permission was denied but the OS still allows another prompt.
  deniedOnce,

  /// Permission was permanently denied; another prompt would no-op and
  /// the rider must open the app settings page to re-enable it.
  deniedForever,

  /// Restricted by parental controls or device policy.
  restricted,
}
