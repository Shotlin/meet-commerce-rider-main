import 'package:permission_handler/permission_handler.dart' as ph;

import '../utils/app_logger.dart';
import 'camera_permission_status.dart';

/// Thin transport seam between [CameraPermissionService] and
/// `permission_handler`, mirroring `LocationPermissionPort` in
/// `location_permission_service.dart` — an `abstract interface class` so
/// tests can supply a hand-rolled double without a platform-channel
/// binding.
abstract interface class CameraPermissionPort {
  /// `Permission.camera.status`.
  Future<ph.PermissionStatus> status();

  /// `Permission.camera.request()`.
  Future<ph.PermissionStatus> request();

  /// `permission_handler.openAppSettings()`.
  Future<bool> openAppSettings();
}

/// Production [CameraPermissionPort] backed by the real plugin.
class _PermissionHandlerCameraPort implements CameraPermissionPort {
  const _PermissionHandlerCameraPort();

  @override
  Future<ph.PermissionStatus> status() => ph.Permission.camera.status;

  @override
  Future<ph.PermissionStatus> request() => ph.Permission.camera.request();

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();
}

/// Camera-permission gate for the QR pickup scanner.
///
/// `mobile_scanner` does not manage OS permission prompts itself the way
/// `image_picker` does for the proof-photo flow — this service must be
/// called explicitly before opening the scanner screen. Structured to
/// match [LocationPermissionService] exactly (same port-injection pattern,
/// same `check()`/`ensure()` split) so it reads as the same idiom.
class CameraPermissionService {
  /// Production constructor: wires to the real permission_handler plugin.
  CameraPermissionService() : _port = const _PermissionHandlerCameraPort();

  /// Test constructor: accepts a custom [CameraPermissionPort].
  CameraPermissionService.withPort(CameraPermissionPort port) : _port = port;

  final CameraPermissionPort _port;

  /// Current permission state without prompting.
  Future<CameraPermissionState> check() async {
    final ph.PermissionStatus raw = await _port.status();
    final CameraPermissionState result = _map(raw);
    AppLogger.info(LogTopic.delivery, 'camera check() -> ${result.name}');
    return result;
  }

  /// Resolves the rider's camera permission, prompting once if needed.
  ///
  /// Mirrors [LocationPermissionService.ensureWhileInUse]: only prompts
  /// when the current state allows another prompt ([CameraPermissionState.deniedOnce]
  /// or not yet determined); [granted]/[deniedForever]/[restricted] are
  /// returned as-is since a prompt would be redundant or a no-op.
  Future<CameraPermissionState> ensure() async {
    final ph.PermissionStatus initialRaw = await _port.status();
    final CameraPermissionState initial = _map(initialRaw);

    if (initial != CameraPermissionState.deniedOnce) {
      AppLogger.info(
        LogTopic.delivery,
        'camera ensure() skipping prompt (state=${initial.name})',
      );
      return initial;
    }

    AppLogger.info(LogTopic.delivery, 'camera ensure() prompting');
    final ph.PermissionStatus afterPromptRaw = await _port.request();
    final CameraPermissionState finalState = _map(afterPromptRaw);
    AppLogger.info(
      LogTopic.delivery,
      'camera ensure() prompt result -> ${finalState.name}',
    );
    return finalState;
  }

  /// Opens the app's settings page so the rider can re-enable a
  /// permanently denied camera permission.
  Future<bool> openAppSettings() async {
    final bool opened = await _port.openAppSettings();
    AppLogger.info(
      LogTopic.delivery,
      'camera openAppSettings() -> opened=$opened',
    );
    return opened;
  }

  static CameraPermissionState _map(ph.PermissionStatus raw) {
    switch (raw) {
      case ph.PermissionStatus.granted:
      case ph.PermissionStatus.limited:
      case ph.PermissionStatus.provisional:
        return CameraPermissionState.granted;
      case ph.PermissionStatus.denied:
        return CameraPermissionState.deniedOnce;
      case ph.PermissionStatus.permanentlyDenied:
        return CameraPermissionState.deniedForever;
      case ph.PermissionStatus.restricted:
        return CameraPermissionState.restricted;
    }
  }
}
