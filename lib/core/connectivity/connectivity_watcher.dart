import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Wraps `connectivity_plus` to expose a simple online/offline boolean
/// stream.
///
/// `connectivity_plus` reports a list of [ConnectivityResult] values
/// (e.g. wifi + vpn, mobile + ethernet). We collapse them into a single
/// `isOffline` boolean: a device is considered offline iff every entry
/// in the latest list is `ConnectivityResult.none`. An empty list is
/// treated as offline as a defensive guard.
///
/// The stream is debounced (default 250ms) to ignore brief flips while
/// the OS hands off between transports (Wi-Fi → cellular), and goes
/// through `.distinct()` so duplicate consecutive states never emit.
///
/// Used by:
/// - the offline banner overlay (`AppOfflineBanner` in shared widgets),
/// - the Location_Uploader to flip into REST-fallback mode immediately,
/// - the Socket_Client for proactive reconnect on regain.
class ConnectivityWatcher {
  /// Constructs a watcher backed by [_connectivity], with an optional
  /// [debounce] window for emission stability.
  ConnectivityWatcher(
    this._connectivity, {
    this.debounce = const Duration(milliseconds: 250),
  });

  final Connectivity _connectivity;

  /// Debounce window applied before publishing a new value. Configurable
  /// for tests; production callers use the default.
  final Duration debounce;

  /// Cold-on-demand stream of `isOffline` booleans, debounced and
  /// distinct. Subscribers receive a value on each settled connectivity
  /// change.
  Stream<bool> get isOffline => _connectivity.onConnectivityChanged
      .map<bool>(_isOfflineFor)
      .transform<bool>(_DebounceTransformer<bool>(debounce))
      .distinct();

  /// Reads the current connectivity state synchronously (returns a
  /// `Future<bool>` because the underlying check is async).
  ///
  /// Use this on cold paths (splash, app resume) where waiting on a
  /// stream emission is awkward.
  Future<bool> currentIsOffline() async {
    final List<ConnectivityResult> results = await _connectivity
        .checkConnectivity();
    return _isOfflineFor(results);
  }

  @visibleForTesting
  static bool isOfflineFor(List<ConnectivityResult> results) =>
      _isOfflineFor(results);

  static bool _isOfflineFor(List<ConnectivityResult> results) {
    if (results.isEmpty) return true;
    return results.every(
      (ConnectivityResult r) => r == ConnectivityResult.none,
    );
  }
}

/// Tiny stream transformer that delays emissions until [window] has
/// elapsed without a new event. Implemented inline so the watcher does
/// not need a third-party rxdart dependency just for one debounce.
class _DebounceTransformer<T> implements StreamTransformer<T, T> {
  _DebounceTransformer(this.window);

  final Duration window;

  @override
  Stream<T> bind(Stream<T> stream) {
    final StreamController<T> controller = stream.isBroadcast
        ? StreamController<T>.broadcast(sync: false)
        : StreamController<T>(sync: false);
    Timer? timer;
    late StreamSubscription<T> sub;
    T? lastValue;
    bool hasValue = false;
    bool sourceDone = false;

    void flush() {
      if (hasValue) {
        controller.add(lastValue as T);
        hasValue = false;
      }
      if (sourceDone && !controller.isClosed) {
        controller.close();
      }
    }

    controller
      ..onListen = () {
        sub = stream.listen(
          (T value) {
            lastValue = value;
            hasValue = true;
            timer?.cancel();
            timer = Timer(window, flush);
          },
          onError: controller.addError,
          onDone: () {
            sourceDone = true;
            timer?.cancel();
            flush();
          },
          cancelOnError: false,
        );
      }
      ..onCancel = () async {
        timer?.cancel();
        await sub.cancel();
      };

    return controller.stream;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() {
    return StreamTransformer.castFrom<T, T, RS, RT>(this);
  }
}
