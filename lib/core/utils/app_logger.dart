import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../config/flavor.dart';

/// Coarse-grained log topics. Used as the `name` argument to
/// `dart:developer.log`, which renders nicely in the Flutter DevTools log
/// view and lets us filter for a single subsystem at a time.
enum LogTopic {
  /// Authentication, OTP, refresh, logout.
  auth('AUTH'),

  /// Socket.IO transport: connect / disconnect / reconnect / token rotation.
  socket('SOCKET'),

  /// Geolocator stream, throttling, REST/socket fallback, profile changes.
  location('LOCATION'),

  /// Riverpod provider lifecycle and notable state changes.
  state('STATE'),

  /// JSON parsing for backend models (DeliveryOrder etc.).
  parse('PARSE'),

  /// App startup pipeline.
  boot('BOOT'),

  /// Firebase Cloud Messaging — token, permissions, foreground messages.
  notifications('NOTIF'),

  /// QR pickup scanning and multi-order batch lifecycle.
  delivery('DELIVERY');

  const LogTopic(this.tag);

  /// Short uppercase tag rendered in log output.
  final String tag;
}

/// Severity levels recognized by [AppLogger]. Mapped onto
/// `dart:developer.log` levels (using approximate Java logging values) so
/// the IDE and DevTools can colour-code them.
enum LogLevel {
  debug(500),
  info(800),
  warn(900),
  error(1000),
  fatal(1200);

  const LogLevel(this.value);

  /// Numeric level forwarded to `dart:developer.log`.
  final int value;
}

/// Lightweight wrapper around `dart:developer.log` with topic tags.
///
/// Three reasons we don't pull in a third-party logging package:
/// 1. We deliberately keep the dependency surface small.
/// 2. `dart:developer.log` is what DevTools actually consumes.
/// 3. Suppressing `debug` in `prod` is a one-line check and does not need
///    a configurable framework.
///
/// In `prod` builds, [LogLevel.debug] entries are dropped before reaching
/// `dart:developer.log`, which keeps the production console quiet without
/// requiring a separate release shim.
class AppLogger {
  AppLogger._();

  /// Resolves the active flavor on every call.
  ///
  /// We don't cache because [Env.current] is itself memoized and tests can
  /// exercise different flavors without reaching for a static reset.
  static AppFlavor get _flavor => Env.current.flavor;

  /// Returns true if a message at [level] should be emitted under the
  /// current flavor.
  ///
  /// `prod` suppresses [LogLevel.debug]; everything else passes through.
  static bool _shouldLog(LogLevel level) {
    if (_flavor.isProd && level == LogLevel.debug) {
      return false;
    }
    return true;
  }

  /// Core log emitter. Public callers go through [debug] / [info] / etc.
  static void _log(
    LogLevel level,
    LogTopic topic,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_shouldLog(level)) return;
    developer.log(
      message,
      name: topic.tag,
      level: level.value,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Verbose / step-level log. Suppressed in `prod`.
  static void debug(LogTopic topic, String message) {
    _log(LogLevel.debug, topic, message);
  }

  /// Notable but expected event (e.g., login success, socket connect).
  static void info(LogTopic topic, String message) {
    _log(LogLevel.info, topic, message);
  }

  /// Recoverable problem (e.g., dropped sample, retried request).
  static void warn(
    LogTopic topic,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.warn, topic, message, error: error, stackTrace: stackTrace);
  }

  /// Recoverable failure that the user should see (e.g., upload failed).
  static void error(
    LogTopic topic,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.error, topic, message, error: error, stackTrace: stackTrace);
  }

  /// Unrecoverable error from `FlutterError.onError` or
  /// `PlatformDispatcher.instance.onError`.
  ///
  /// Today this is a no-op beyond the `dart:developer.log` call; the
  /// `ErrorReporter` seam in the design will plug in real crash reporting
  /// in a later phase.
  static void fatal(
    LogTopic topic,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.fatal, topic, message, error: error, stackTrace: stackTrace);
  }

  /// Riverpod provider observer that funnels lifecycle events through
  /// [AppLogger]. Wired into the `ProviderScope` from `bootstrap()`.
  ///
  /// Only emits at [LogLevel.debug] so production builds stay silent for
  /// provider churn, while dev builds get a usable trace of state changes.
  static ProviderObserver providerObserver() => _AppLoggerProviderObserver();
}

/// Implementation detail of [AppLogger.providerObserver].
///
/// Kept private so the only entry point is the factory above. `base`
/// because Riverpod 3 declares `ProviderObserver` as `abstract base`.
final class _AppLoggerProviderObserver extends ProviderObserver {
  _AppLoggerProviderObserver();

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    AppLogger.debug(
      LogTopic.state,
      'add ${context.provider} = ${_describe(value)}',
    );
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    AppLogger.debug(
      LogTopic.state,
      'update ${context.provider}: '
      '${_describe(previousValue)} -> ${_describe(newValue)}',
    );
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    AppLogger.debug(LogTopic.state, 'dispose ${context.provider}');
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    AppLogger.error(
      LogTopic.state,
      'fail ${context.provider}',
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Best-effort, non-throwing description for arbitrary state values.
  ///
  /// We never want a logging side effect to bring down the app, so any
  /// exception during `toString` is swallowed and replaced with the type.
  String _describe(Object? value) {
    if (value == null) return 'null';
    try {
      final s = value.toString();
      if (s.length <= 200) return s;
      return '${s.substring(0, 200)}...';
    } catch (_) {
      return describeIdentity(value);
    }
  }
}
