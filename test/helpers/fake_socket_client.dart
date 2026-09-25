import 'dart:async';

import 'package:meet_commerce_rider_main/core/realtime/socket_client.dart';

/// A captured emit recorded by [FakeSocketClient].
class CapturedEmit {
  /// Constructs an emit record.
  CapturedEmit(this.event, this.payload);

  /// Event name.
  final String event;

  /// Payload.
  final Map<String, dynamic> payload;

  @override
  String toString() => 'CapturedEmit($event, $payload)';
}

/// Test double for [SocketClient].
///
/// Records every [emit] call into [emittedEvents]. Tests can drive the
/// connection [status] via [fakeStatus] and push synthetic events
/// through [pushEvent] to exercise listeners registered via [on].
class FakeSocketClient implements SocketClient {
  /// Constructs a disconnected fake client.
  FakeSocketClient({SocketStatus status = SocketStatus.disconnected})
    : _status = status;

  SocketStatus _status;

  /// Test-controllable status. Setting this also fires a status update
  /// through [statusStream].
  set fakeStatus(SocketStatus s) {
    if (_status == s) return;
    _status = s;
    _statusController.add(s);
  }

  @override
  SocketStatus get status => _status;

  final StreamController<SocketStatus> _statusController =
      StreamController<SocketStatus>.broadcast();

  @override
  Stream<SocketStatus> get statusStream => _statusController.stream;

  final List<CapturedEmit> emittedEvents = <CapturedEmit>[];

  /// Captures of [connect] / [reconnectWithToken] tokens.
  final List<String> connectTokens = <String>[];

  /// True when [disconnect] has been called.
  bool disconnected = false;

  final Map<String, StreamController<Map<String, dynamic>>> _eventControllers =
      <String, StreamController<Map<String, dynamic>>>{};

  @override
  void emit(String event, Map<String, dynamic> payload) {
    if (_status != SocketStatus.connected) return;
    emittedEvents.add(CapturedEmit(event, payload));
  }

  @override
  Stream<Map<String, dynamic>> on(String event) {
    final StreamController<Map<String, dynamic>>? existing =
        _eventControllers[event];
    if (existing != null) return existing.stream;
    final StreamController<Map<String, dynamic>> c =
        StreamController<Map<String, dynamic>>.broadcast();
    _eventControllers[event] = c;
    return c.stream;
  }

  /// Pushes a synthetic [payload] for [event] to any active subscribers.
  ///
  /// Returns synchronously after the controller has accepted the
  /// payload; subscribers receive it asynchronously per Dart's event
  /// loop.
  void pushEvent(String event, Map<String, dynamic> payload) {
    final StreamController<Map<String, dynamic>>? c = _eventControllers[event];
    if (c == null || c.isClosed) return;
    c.add(payload);
  }

  @override
  Future<void> connect(String accessToken) async {
    connectTokens.add(accessToken);
    fakeStatus = SocketStatus.connected;
  }

  @override
  void reconnectWithToken(String newAccessToken) {
    connectTokens.add(newAccessToken);
    fakeStatus = SocketStatus.connected;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
    fakeStatus = SocketStatus.disconnected;
  }

  @override
  Future<void> dispose() async {
    for (final StreamController<Map<String, dynamic>> c
        in _eventControllers.values) {
      await c.close();
    }
    _eventControllers.clear();
    if (!_statusController.isClosed) {
      await _statusController.close();
    }
  }
}
