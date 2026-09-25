import 'package:workmanager/workmanager.dart';

/// Unique task name registered with WorkManager.
///
/// Used as both the [Workmanager.registerPeriodicTask] unique name and
/// the task identifier passed to [callbackDispatcher].
const String kRiderLocationTaskName = 'meetcommerce_rider_location_heartbeat';

/// Minimum interval between periodic location heartbeat executions.
///
/// Android enforces a minimum of 15 minutes for periodic work. This
/// value matches that floor so the OS never silently bumps it up.
const Duration kRiderLocationTaskInterval = Duration(minutes: 15);

/// Top-level WorkManager callback dispatcher.
///
/// Must be a **top-level function** annotated with `@pragma('vm:entry-point')`
/// so the Dart AOT compiler keeps it alive in release builds (the
/// background isolate calls it directly via the Android WorkManager
/// JNI bridge without going through normal Dart entry points).
///
/// Register once in [bootstrap] via:
/// ```dart
/// await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
/// ```
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((
    String taskName,
    Map<String, dynamic>? inputData,
  ) async {
    switch (taskName) {
      case kRiderLocationTaskName:
        // The foreground [LocationLifecycleManager] owns the live GPS
        // stream while the app is in the foreground. This periodic task
        // fires when the system has backgrounded / killed the process;
        // its job is simply to keep the WorkManager slot warm so Android
        // does not evict the foreground-service declaration, preserving
        // our ability to restart the stream on the next app resume.
        //
        // Full background GPS tracking (R29) will be added in a later
        // milestone once the backend location-log endpoint is audited.
        return true;

      default:
        return true;
    }
  });
}
