import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/realtime/socket_events.dart';

/// Trivial constant-value tests for [SocketEvents].
///
/// These tests exist to catch accidental renames or typos in the event-name
/// constants. The backend contract defines these strings; any mismatch would
/// cause silent failures at runtime.
void main() {
  group('SocketEvents constants match backend contract', () {
    // Inbound events (server → rider)
    test('orderAssigned is "order:assigned"', () {
      expect(SocketEvents.orderAssigned, 'order:assigned');
    });

    test('orderExpired is "order:expired"', () {
      expect(SocketEvents.orderExpired, 'order:expired');
    });

    test('orderStatus is "order:status"', () {
      expect(SocketEvents.orderStatus, 'order:status');
    });

    test('notification is "notification"', () {
      expect(SocketEvents.notification, 'notification');
    });

    // Outbound events (rider → server)
    test('riderLocation is "rider:location"', () {
      expect(SocketEvents.riderLocation, 'rider:location');
    });

    test('riderOffline is "rider:offline"', () {
      expect(SocketEvents.riderOffline, 'rider:offline');
    });

    test('orderTrack is "order:track"', () {
      expect(SocketEvents.orderTrack, 'order:track');
    });

    test('orderUntrack is "order:untrack"', () {
      expect(SocketEvents.orderUntrack, 'order:untrack');
    });

    test('all constants are non-empty strings', () {
      final constants = <String>[
        SocketEvents.orderAssigned,
        SocketEvents.orderExpired,
        SocketEvents.orderStatus,
        SocketEvents.notification,
        SocketEvents.riderLocation,
        SocketEvents.riderOffline,
        SocketEvents.orderTrack,
        SocketEvents.orderUntrack,
      ];
      for (final c in constants) {
        expect(c, isNotEmpty, reason: 'constant "$c" must not be empty');
      }
    });

    test('all constants are unique', () {
      final constants = <String>[
        SocketEvents.orderAssigned,
        SocketEvents.orderExpired,
        SocketEvents.orderStatus,
        SocketEvents.notification,
        SocketEvents.riderLocation,
        SocketEvents.riderOffline,
        SocketEvents.orderTrack,
        SocketEvents.orderUntrack,
      ];
      expect(
        constants.toSet().length,
        constants.length,
        reason: 'all event name constants must be unique',
      );
    });
  });
}
