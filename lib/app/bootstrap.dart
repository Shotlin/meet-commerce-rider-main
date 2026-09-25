import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../core/background/background_location_task.dart';
import '../core/config/env.dart';
import '../core/notifications/notification_service.dart';
import '../core/utils/app_logger.dart';

/// Builder signature for the app's root widget.
///
/// Asynchronous so that future bootstrap stages (router config, theme
/// hydration) can do I/O before the first frame.
typedef AppBuilder = Future<Widget> Function();

/// Initializes the Flutter binding, applies global system chrome, resolves
/// [Env.current], and hands the supplied [builder]'s root widget to
/// `runApp`, wrapped in a Riverpod [ProviderScope].
///
/// Catches uncaught Flutter framework errors via [FlutterError.onError] and
/// uncaught platform / async errors via
/// `PlatformDispatcher.instance.onError`, forwarding both to
/// [AppLogger.fatal]. Real crash reporting is intentionally deferred (see
/// the `ErrorReporter` seam in the design); this wiring guarantees that when
/// it does land, the integration point is already correct.
///
/// Run inside `runZonedGuarded` so any zone-level errors that escape the
/// platform dispatcher (e.g., from a `Future` started off the main isolate)
/// are still captured.
Future<void> bootstrap(AppBuilder builder) async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Premium minimal chrome: status bar icons sit on top of white
      // surfaces, the navigation bar matches the scaffold background.
      // We set this once at boot so screens don't have to redeclare it
      // unless they intentionally invert (e.g., a dark map sheet).
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      );

      // Rider operations assume a portrait device (map + bottom sheet
      // composition). Landscape is intentionally not supported in MVP.
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);

      // Initialize Firebase and FCM (fire-and-forget; failures are logged
      // but must not prevent the app from starting).
      unawaited(NotificationService.instance.initialize());

      // Initialize WorkManager so the periodic location heartbeat task
      // survives app backgrounding / process death on Android 8+.
      // isInDebugMode=false suppresses the extra WorkManager notification
      // in release builds; flip to true when diagnosing background-task
      // scheduling issues.
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
      // Register (or replace) the periodic heartbeat. WorkManager
      // deduplicates by uniqueName so calling this on every cold-start
      // is safe — it simply refreshes the existing registration.
      await Workmanager().registerPeriodicTask(
        kRiderLocationTaskName,
        kRiderLocationTaskName,
        frequency: kRiderLocationTaskInterval,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );

      // Resolve and log the active environment so DevTools makes the
      // backend target obvious for QA/demo builds.
      final env = Env.current;
      AppLogger.info(
        LogTopic.boot,
        'Bootstrap start: flavor=${env.flavor.name} '
        'apiBaseUrl=${env.apiBaseUrl} '
        'socketBaseUrl=${env.socketBaseUrl} '
        'devAffordances=${env.enableDevAffordances}',
      );

      // Route framework errors through the logger. We delegate to the
      // default presenter for in-app behavior (red error widget in debug,
      // silent in release) so we don't change UX, only telemetry.
      FlutterError.onError = (FlutterErrorDetails details) {
        AppLogger.fatal(
          LogTopic.boot,
          'FlutterError: ${details.exceptionAsString()}',
          error: details.exception,
          stackTrace: details.stack,
        );
        FlutterError.presentError(details);
      };

      // Route async / platform errors through the logger. Returning true
      // marks the error as handled so the engine does not re-emit it.
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        AppLogger.fatal(
          LogTopic.boot,
          'PlatformDispatcher error',
          error: error,
          stackTrace: stack,
        );
        return true;
      };

      final root = await builder();

      runApp(
        ProviderScope(
          observers: <ProviderObserver>[AppLogger.providerObserver()],
          child: root,
        ),
      );

      AppLogger.info(LogTopic.boot, 'Bootstrap complete');
    },
    (Object error, StackTrace stack) {
      AppLogger.fatal(
        LogTopic.boot,
        'Uncaught zone error',
        error: error,
        stackTrace: stack,
      );
    },
  );
}
