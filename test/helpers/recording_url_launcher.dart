import 'package:meet_commerce_rider_main/core/utils/external_nav_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

/// A captured `launch` call recorded by [RecordingUrlLauncher].
class CapturedLaunch {
  /// Constructs a launch record.
  const CapturedLaunch(this.uri, this.mode);

  /// URI passed to `launch`.
  final Uri uri;

  /// Launch mode used.
  final LaunchMode mode;

  @override
  String toString() => 'CapturedLaunch($uri, $mode)';
}

/// Test double for [UrlLauncherDelegate].
///
/// Records every [canLaunch] check and [launch] call so tests can
/// assert on the exact URL being launched and the launch mode chosen
/// without touching the platform.
///
/// Defaults to [canLaunch] returning `true` and [launch] succeeding;
/// flip [canLaunchResult] / [launchSucceeds] to model failure cases.
class RecordingUrlLauncher implements UrlLauncherDelegate {
  /// Constructs a recording launcher.
  RecordingUrlLauncher({
    this.canLaunchResult = true,
    this.launchSucceeds = true,
    this.throwOnExternal = false,
  });

  /// Whether [canLaunch] returns true.
  bool canLaunchResult;

  /// Whether [launch] returns true (modelling a successful launch).
  bool launchSucceeds;

  /// When true, [launch] throws on the first call with
  /// [LaunchMode.externalApplication]. Used to verify the fallback
  /// branch in [ExternalNavigationLauncher.openDrivingDirections].
  bool throwOnExternal;

  /// Recorded [canLaunch] checks.
  final List<Uri> canLaunchCalls = <Uri>[];

  /// Recorded [launch] calls.
  final List<CapturedLaunch> launchCalls = <CapturedLaunch>[];

  @override
  Future<bool> canLaunch(Uri uri) async {
    canLaunchCalls.add(uri);
    return canLaunchResult;
  }

  @override
  Future<bool> launch(Uri uri, {required LaunchMode mode}) async {
    if (throwOnExternal && mode == LaunchMode.externalApplication) {
      throwOnExternal = false; // only throw the first time
      throw StateError('external app unavailable');
    }
    launchCalls.add(CapturedLaunch(uri, mode));
    return launchSucceeds;
  }
}
