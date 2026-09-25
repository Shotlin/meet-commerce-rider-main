import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../utils/app_logger.dart';
import 'socket_events.dart';

/// Connection state of the [SocketClient].
enum SocketStatus {
  /// No socket exists or the socket has been cleanly disconnected.
  disconnected,

  /// The socket is in the process of connecting or reconnecting.
  connecting,

  /// The socket is connected and ready to emit/receive events.
  connected,
}

/// Realtime transport surface used by the rider app.
///
/// `SocketClient` is the seam between the application layer and
/// `socket_io_client`. The concrete production implementation
/// ([IoSocketClient]) wraps the real Socket.IO client; tests provide a
/// fake that exposes test-only injection points without touching the
/// network.
///
/// Public surface:
/// - [statusStream] / [status]: connection status (R7.4).
/// - [on]: per-event broadcast stream of decoded payloads.
/// - [emit]: fire-and-forget send (silently dropped while disconnected).
/// - [connect]: open the socket using the supplied access token (R7.1).
/// - [reconnectWithToken]: tear down and reopen with a rotated token
///   without losing application-level subscriptions (R7.2).
/// - [disconnect]: emit `rider:offline` and close the transport (R7.6).
abstract interface class SocketClient {
  /// Builds the production [IoSocketClient] pointed at [socketBaseUrl].
  factory SocketClient.io({required String socketBaseUrl}) = IoSocketClient._;

  /// Latest known connection status.
  SocketStatus get status;

  /// Broadcasts every [SocketStatus] transition.
  Stream<SocketStatus> get statusStream;

  /// Returns a broadcast stream for [event].
  ///
  /// The same stream instance is returned for repeated calls with the
  /// same [event] name so multiple subscribers never duplicate the
  /// underlying socket listener.
  ///
  /// Stream values are always `Map<String, dynamic>`. Non-map payloads
  /// (plain strings, lists) are wrapped in `{'value': raw}` so callers
  /// always receive a map even when the backend sends a primitive.
  Stream<Map<String, dynamic>> on(String event);

  /// Emits [event] with [payload].
  ///
  /// Dropped silently when [status] is not [SocketStatus.connected].
  void emit(String event, Map<String, dynamic> payload);

  /// Opens the socket using [accessToken] for the `auth` payload.
  ///
  /// Safe to call multiple times: an existing socket is torn down
  /// first so the rider always has at most one live transport.
  Future<void> connect(String accessToken);

  /// Tears down the current socket and reconnects with [newAccessToken].
  ///
  /// Application-level subscriptions registered via [on] are preserved:
  /// the stream controllers persist across reconnects and the new
  /// underlying socket re-attaches to the same controllers (R7.2).
  void reconnectWithToken(String newAccessToken);

  /// Emits `rider:offline`, removes all listeners, and closes the
  /// transport. Idempotent (R7.6).
  Future<void> disconnect();

  /// Releases the status stream. Call when the provider is disposed.
  Future<void> dispose();
}

/// Production [SocketClient] backed by `socket_io_client`.
///
/// Configuration (R7.1, R7.3, [AppConstants]):
/// - Transport: websocket only.
/// - Auto-connect: disabled (caller calls [connect] explicitly).
/// - Reconnection: enabled; base 1 s delay, 30 s cap, 0.5 jitter.
class IoSocketClient implements SocketClient {
  /// Internal constructor used by [SocketClient.io].
  IoSocketClient._({required String socketBaseUrl})
    : _socketBaseUrl = socketBaseUrl;

  /// Test-only constructor that allows substituting the underlying
  /// socket builder. Production code MUST go through [SocketClient.io].
  @visibleForTesting
  IoSocketClient.forTesting({
    required String socketBaseUrl,
    io.Socket Function(String url, Map<String, dynamic> options)? socketBuilder,
  }) : _socketBaseUrl = socketBaseUrl,
       _socketBuilder = socketBuilder ?? _defaultSocketBuilder;

  final String _socketBaseUrl;

  io.Socket Function(String url, Map<String, dynamic> options) _socketBuilder =
      _defaultSocketBuilder;

  io.Socket? _socket;
  String? _currentToken;

  SocketStatus _status = SocketStatus.disconnected;
  final StreamController<SocketStatus> _statusController =
      StreamController<SocketStatus>.broadcast();

  /// Map of event-name -> broadcast controller. The same controller is
  /// reused across reconnects so subscribers never need to re-listen
  /// after a token rotation.
  final Map<String, StreamController<Map<String, dynamic>>> _eventControllers =
      <String, StreamController<Map<String, dynamic>>>{};

  @override
  SocketStatus get status => _status;

  @override
  Stream<SocketStatus> get statusStream => _statusController.stream;

  // ---------------------------------------------------------------------------
  // connect / disconnect / reconnect
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect(String accessToken) async {
    _currentToken = accessToken;
    _teardownSocket();
    _updateStatus(SocketStatus.connecting);

    final io.Socket socket = _socketBuilder(_socketBaseUrl, <String, dynamic>{
      'transports': <String>['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 30000,
      'randomizationFactor': 0.5,
      'auth': <String, dynamic>{'token': accessToken},
    });
    _socket = socket;

    socket
      ..onConnect((_) {
        AppLogger.info(LogTopic.socket, 'Socket connected to $_socketBaseUrl');
        _updateStatus(SocketStatus.connected);
      })
      ..onDisconnect((_) {
        AppLogger.info(LogTopic.socket, 'Socket disconnected');
        _updateStatus(SocketStatus.disconnected);
      })
      ..onConnectError((dynamic err) {
        AppLogger.warn(LogTopic.socket, 'Socket connect_error: $err');
        // Reconnection is handled by the socket_io_client library's
        // built-in exponential backoff; we simply track status.
        _updateStatus(SocketStatus.disconnected);
      })
      ..onReconnectAttempt((dynamic attempt) {
        AppLogger.debug(LogTopic.socket, 'Socket reconnect attempt $attempt');
        _updateStatus(SocketStatus.connecting);
      });

    // Re-attach every previously registered application-level listener
    // to this fresh socket so [reconnectWithToken] doesn't lose
    // subscriptions registered via [on].
    for (final MapEntry<String, StreamController<Map<String, dynamic>>> entry
        in _eventControllers.entries) {
      _attachSocketListener(entry.key, entry.value);
    }

    socket.connect();
  }

  @override
  void reconnectWithToken(String newAccessToken) {
    AppLogger.info(LogTopic.socket, 'Rotating socket auth token');
    _teardownSocket();
    // Fire-and-forget: connect() is async but token rotation is a
    // fire-and-forget signal from the auth interceptor. The status
    // stream is the canonical way to observe completion.
    unawaited(connect(newAccessToken));
  }

  @override
  Future<void> disconnect() async {
    if (_status == SocketStatus.connected) {
      _socket?.emit(SocketEvents.riderOffline, <String, dynamic>{});
    }
    _teardownSocket();
    _updateStatus(SocketStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    _teardownSocket();
    for (final StreamController<Map<String, dynamic>> c
        in _eventControllers.values) {
      await c.close();
    }
    _eventControllers.clear();
    if (!_statusController.isClosed) {
      await _statusController.close();
    }
  }

  // ---------------------------------------------------------------------------
  // emit / on
  // ---------------------------------------------------------------------------

  @override
  void emit(String event, Map<String, dynamic> payload) {
    if (_status != SocketStatus.connected) return;
    _socket?.emit(event, payload);
  }

  @override
  Stream<Map<String, dynamic>> on(String event) {
    final StreamController<Map<String, dynamic>>? existing =
        _eventControllers[event];
    if (existing != null) return existing.stream;

    final StreamController<Map<String, dynamic>> controller =
        StreamController<Map<String, dynamic>>.broadcast();
    _eventControllers[event] = controller;
    _attachSocketListener(event, controller);
    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _attachSocketListener(
    String event,
    StreamController<Map<String, dynamic>> sink,
  ) {
    final io.Socket? socket = _socket;
    if (socket == null) return;

    // Replace any existing listener for this event on the underlying
    // socket so we never double-fire after a reconnect.
    socket.off(event);
    socket.on(event, (dynamic data) {
      if (sink.isClosed) return;
      sink.add(_normalizePayload(data));
    });
  }

  Map<String, dynamic> _normalizePayload(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map<String, dynamic>(
        (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
      );
    }
    return <String, dynamic>{'value': data};
  }

  void _updateStatus(SocketStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _teardownSocket() {
    final io.Socket? socket = _socket;
    if (socket == null) return;
    try {
      socket.clearListeners();
      socket.disconnect();
      socket.dispose();
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.socket,
        'SocketClient teardown failed (ignoring)',
        error: e,
        stackTrace: stack,
      );
    }
    _socket = null;
  }

  /// Most recent token passed to [connect] / [reconnectWithToken]. Kept
  /// so future telemetry hooks can inspect token rotation without
  /// reaching into private fields. Currently unused.
  // ignore: unused_element
  String? get _debugCurrentToken => _currentToken;

  static io.Socket _defaultSocketBuilder(
    String url,
    Map<String, dynamic> options,
  ) {
    return io.io(url, options);
  }
}
