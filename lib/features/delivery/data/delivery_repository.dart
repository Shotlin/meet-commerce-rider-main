import 'dart:io';

import '../../../core/network/api_envelope.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/delivery_history_entry.dart';
import '../domain/delivery_order.dart';
import '../domain/payout.dart';
import '../domain/pickup_session.dart';
import '../domain/rider_earnings.dart';
import '../domain/rider_profile.dart';
import '../domain/rider_stats.dart';
import '../domain/store_info.dart';
import 'delivery_api.dart';

/// Thin pass-through wrapper around [DeliveryApi].
///
/// Responsibilities:
/// - Forward each call to [DeliveryApi] without extra business logic.
/// - Translate `ORDER_NOT_AVAILABLE` envelope errors into the typed
///   [OrderNotAvailableException] the application layer pattern-matches
///   on.
/// - Translate the `toggle-online` HTTP 500 backend bug into
///   [RiderNotApprovedError] so the UI can route to the approval
///   screen.
/// - Log errors via [AppLogger] before they propagate.
///
/// The repository deliberately does **not** cache responses; caching
/// is a controller-layer concern (see `EarningsController`,
/// `HistoryController`).
class DeliveryRepository {
  /// Wires the repository to its [api].
  DeliveryRepository(this._api);

  final DeliveryApi _api;

  // ---------------------------------------------------------------------------
  // Profile & documents
  // ---------------------------------------------------------------------------

  /// Fetches the rider's profile.
  Future<RiderProfile> getProfile() => _api.getProfile();

  /// Fetches the rider's uploaded documents.
  Future<List<Map<String, dynamic>>> getDocuments() => _api.getDocuments();

  /// Toggles the rider's online/offline status.
  ///
  /// Translates [ApiServerException] (and an explicit
  /// [RiderNotApprovedError] from the API layer) into
  /// [RiderNotApprovedError] so the application layer can route to the
  /// approval screen on the live backend's HTTP 500 bug.
  Future<void> toggleOnline(bool isOnline) async {
    try {
      await _api.toggleOnline(isOnline);
    } on RiderNotApprovedError {
      rethrow;
    } on ApiServerException catch (e, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'toggle-online returned 5xx: ${e.message}',
        error: e,
        stackTrace: stack,
      );
      throw const RiderNotApprovedError();
    }
  }

  // ---------------------------------------------------------------------------
  // Orders
  // ---------------------------------------------------------------------------

  /// Fetches the rider's current orders.
  Future<List<DeliveryOrder>> getOrders({String? status}) =>
      _api.getOrders(status: status);

  /// Accepts an order offer.
  Future<Map<String, dynamic>> acceptOrder(String orderId) async {
    try {
      return await _api.acceptOrder(orderId);
    } on ApiException catch (e, stack) {
      _logAndTranslate('acceptOrder', orderId, e, stack);
      rethrow;
    }
  }

  /// Rejects an order offer.
  ///
  /// [reason] is the uppercase wire string. Callers typically use
  /// [RejectReason.wire] to obtain the value.
  Future<void> rejectOrder(String orderId, String reason) async {
    try {
      await _api.rejectOrder(orderId, reason);
    } on ApiException catch (e, stack) {
      _logAndTranslate('rejectOrder', orderId, e, stack);
      rethrow;
    }
  }

  /// Cancels a delivery already accepted/picked up.
  ///
  /// [reason] is the uppercase wire string. Callers typically use
  /// [CancelDeliveryReason.wire] to obtain the value.
  Future<void> cancelDelivery(String orderId, String reason) async {
    try {
      await _api.cancelDelivery(orderId, reason);
    } on ApiException catch (e, stack) {
      _logAndTranslate('cancelDelivery', orderId, e, stack);
      rethrow;
    }
  }

  /// Verifies a scanned invoice QR pickup code.
  ///
  /// [payload] carries `{token, v, sig}` only — the QR has no order id
  /// to log until the backend resolves it from the token, which is why
  /// this doesn't go through [_logAndTranslate] (built around an
  /// already-known orderId) like the other action methods here.
  /// Rejections (wrong rider, expired/revoked token, tampered
  /// signature, already-scanned, etc.) surface as [ApiException] with
  /// `e.message` already rider-readable — the caller shows it directly.
  Future<PickupVerification> verifyScan(Map<String, dynamic> payload) async {
    try {
      return await _api.verifyScan(payload);
    } on ApiException catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'DeliveryRepository.verifyScan failed: '
        '${e.backendCode ?? 'no-code'} ${e.message}',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Re-fetches the checklist for an order already scanned (VERIFIED)
  /// but not yet confirmed picked up — see [DeliveryApi.getPendingChecklist].
  /// A `NO_PENDING_CHECKLIST` [ApiException] is an expected, silent
  /// outcome for most orders (means "never scanned, that's fine") rather
  /// than a failure worth logging as a warning — callers check for it
  /// explicitly rather than treating every throw here as unexpected.
  Future<PickupVerification> getPendingChecklist(String orderId) async {
    try {
      return await _api.getPendingChecklist(orderId);
    } on ApiException catch (e, stack) {
      if (e.backendCode != 'NO_PENDING_CHECKLIST') {
        AppLogger.warn(
          LogTopic.state,
          'DeliveryRepository.getPendingChecklist($orderId) failed: '
          '${e.backendCode ?? 'no-code'} ${e.message}',
          error: e,
          stackTrace: stack,
        );
      }
      rethrow;
    }
  }

  /// Marks an order as picked up from the store.
  Future<void> markPickedUp(String orderId) async {
    try {
      await _api.markPickedUp(orderId);
    } on ApiException catch (e, stack) {
      _logAndTranslate('markPickedUp', orderId, e, stack);
      rethrow;
    }
  }

  /// Marks an order as delivered.
  Future<void> markDelivered(
    String orderId, {
    String? proofPhotoUrl,
    bool? demoMode,
    double? cashCollected,
    double? upiCollected,
  }) async {
    try {
      await _api.markDelivered(
        orderId,
        proofPhotoUrl: proofPhotoUrl,
        demoMode: demoMode,
        cashCollected: cashCollected,
        upiCollected: upiCollected,
      );
    } on ApiException catch (e, stack) {
      _logAndTranslate('markDelivered', orderId, e, stack);
      rethrow;
    }
  }

  /// Uploads a proof photo for an order.
  Future<String> uploadProof(String orderId, File file) =>
      _api.uploadProof(orderId, file);

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  /// Updates the rider's current location.
  Future<void> updateLocation(double latitude, double longitude) =>
      _api.updateLocation(latitude, longitude);

  // ---------------------------------------------------------------------------
  // Store info
  // ---------------------------------------------------------------------------

  /// Fetches the store information.
  Future<StoreInfo> getStoreInfo() => _api.getStoreInfo();

  // ---------------------------------------------------------------------------
  // Stats & earnings
  // ---------------------------------------------------------------------------

  /// Fetches the rider's performance statistics.
  Future<RiderStats> getStats() => _api.getStats();

  /// Fetches the rider's earnings for [period].
  Future<RiderEarnings> getEarnings(EarningsPeriod period) =>
      _api.getEarnings(period);

  // ---------------------------------------------------------------------------
  // Payouts & history
  // ---------------------------------------------------------------------------

  /// Fetches the rider's payout history.
  Future<({List<Payout> items, Pagination pagination})> getPayouts({
    int page = 1,
    int limit = 20,
  }) => _api.getPayouts(page: page, limit: limit);

  /// Fetches the rider's delivery history.
  Future<({List<DeliveryHistoryEntry> orders, int total})> getHistory({
    int page = 1,
    int limit = 20,
  }) => _api.getHistory(page: page, limit: limit);

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Logs the failure and rethrows `ORDER_NOT_AVAILABLE` envelopes as
  /// [OrderNotAvailableException]. Other exceptions are logged and
  /// re-raised unchanged by the caller.
  void _logAndTranslate(
    String op,
    String orderId,
    ApiException e,
    StackTrace stack,
  ) {
    AppLogger.warn(
      LogTopic.state,
      'DeliveryRepository.$op($orderId) failed: '
      '${e.backendCode ?? 'no-code'} ${e.message}',
      error: e,
      stackTrace: stack,
    );
    if (e.backendCode == 'ORDER_NOT_AVAILABLE') {
      // Throw inside the catch so the call site sees the typed
      // exception instead of the generic ApiException.
      Error.throwWithStackTrace(OrderNotAvailableException(e.message), stack);
    }
  }
}

/// Thrown when an order is no longer available (backend code
/// `ORDER_NOT_AVAILABLE`).
final class OrderNotAvailableException implements Exception {
  /// Constructs the exception with the backend [message].
  const OrderNotAvailableException([
    this.message = 'Order is no longer available',
  ]);

  /// Human-readable message from the backend.
  final String message;

  @override
  String toString() => 'OrderNotAvailableException: $message';
}
