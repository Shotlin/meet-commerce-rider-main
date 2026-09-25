/// Socket.IO event-name constants shared between the client and the backend.
///
/// Using a single source of truth here prevents typos from causing silent
/// failures (a mismatched event name simply never fires). All names are
/// verified against the SHOTLIN grocery-backend socket contract.
abstract final class SocketEvents {
  // ---------------------------------------------------------------------------
  // Inbound (server → rider)
  // ---------------------------------------------------------------------------

  /// Emitted by the backend when a new delivery is assigned to this rider.
  static const String orderAssigned = 'order:assigned';

  /// Emitted by the backend when an assigned offer has timed out.
  static const String orderExpired = 'order:expired';

  /// Emitted by the backend when the order's status changes.
  static const String orderStatus = 'order:status';

  /// Generic in-app notification from the backend.
  static const String notification = 'notification';

  // ---------------------------------------------------------------------------
  // Outbound (rider → server)
  // ---------------------------------------------------------------------------

  /// Emitted by the rider to stream the current GPS position.
  static const String riderLocation = 'rider:location';

  /// Emitted by the rider when going offline or logging out.
  static const String riderOffline = 'rider:offline';

  /// Emitted by the rider after accepting an order to start tracking.
  static const String orderTrack = 'order:track';

  /// Emitted by the rider after completing a delivery to stop tracking.
  static const String orderUntrack = 'order:untrack';
}
