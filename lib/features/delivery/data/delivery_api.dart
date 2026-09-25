import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/network/api_exception.dart';
import '../domain/delivery_history_entry.dart';
import '../domain/delivery_order.dart';
import '../domain/payout.dart';
import '../domain/pickup_session.dart';
import '../domain/rider_earnings.dart';
import '../domain/rider_profile.dart';
import '../domain/rider_stats.dart';
import '../domain/store_info.dart';

/// Period filter for [DeliveryApi.getEarnings].
///
/// Each value maps to the wire string the live backend expects on the
/// `period` query parameter.
enum EarningsPeriod {
  /// Earnings for the current calendar day.
  today,

  /// Earnings for the current rolling week.
  week,

  /// Earnings for the current calendar month.
  month,

  /// All-time earnings.
  all;

  /// Wire value sent on the `period` query parameter.
  String get wire {
    switch (this) {
      case EarningsPeriod.today:
        return 'today';
      case EarningsPeriod.week:
        return 'week';
      case EarningsPeriod.month:
        return 'month';
      case EarningsPeriod.all:
        return 'all';
    }
  }

  /// Parses [raw] (case-insensitive) into the matching period. Falls
  /// back to [EarningsPeriod.today] when the value is unrecognised.
  static EarningsPeriod parse(String raw) {
    switch (raw.toLowerCase()) {
      case 'today':
        return EarningsPeriod.today;
      case 'week':
        return EarningsPeriod.week;
      case 'month':
        return EarningsPeriod.month;
      case 'all':
        return EarningsPeriod.all;
    }
    return EarningsPeriod.today;
  }
}

/// Reason supplied when a rider rejects an order offer.
///
/// Each value maps to the uppercase wire string the live backend
/// accepts on `PATCH /delivery/orders/:id/reject`.
enum RejectReason {
  /// Pickup or drop-off is too far from the rider's current position.
  tooFar,

  /// Rider's vehicle is unavailable / unsafe to ride.
  vehicleIssue,

  /// Personal reason (illness, break, etc.).
  personalReason,

  /// Catch-all when none of the other reasons apply.
  other;

  /// Wire value (`TOO_FAR`, `VEHICLE_ISSUE`, …).
  String get wire {
    switch (this) {
      case RejectReason.tooFar:
        return 'TOO_FAR';
      case RejectReason.vehicleIssue:
        return 'VEHICLE_ISSUE';
      case RejectReason.personalReason:
        return 'PERSONAL_REASON';
      case RejectReason.other:
        return 'OTHER';
    }
  }
}

/// Reason supplied when a rider cancels a delivery they already
/// accepted/picked up — e.g. the customer refuses the order at the
/// door or can't be reached.
///
/// Each value maps to the uppercase wire string the live backend
/// accepts on `PATCH /delivery/orders/:id/cancel`.
enum CancelDeliveryReason {
  /// Customer refused to accept the order at the door.
  customerRefused,

  /// Customer didn't answer calls or the door.
  customerUnreachable,

  /// Customer wasn't at the delivery address.
  customerNotHome,

  /// Catch-all when none of the other reasons apply.
  other;

  /// Wire value (`CUSTOMER_REFUSED`, `CUSTOMER_UNREACHABLE`, …).
  String get wire {
    switch (this) {
      case CancelDeliveryReason.customerRefused:
        return 'CUSTOMER_REFUSED';
      case CancelDeliveryReason.customerUnreachable:
        return 'CUSTOMER_UNREACHABLE';
      case CancelDeliveryReason.customerNotHome:
        return 'CUSTOMER_NOT_HOME';
      case CancelDeliveryReason.other:
        return 'OTHER';
    }
  }
}

/// Typed error thrown when `toggle-online` fails because the rider
/// profile is not yet approved.
///
/// The Meet Commerce backend returns HTTP 403 with code
/// `RIDER_NOT_APPROVED` for this case; the backendCode is translated
/// here so the caller can route to the approval screen.
final class RiderNotApprovedError implements Exception {
  /// Constructs the error with an optional [message].
  const RiderNotApprovedError([
    this.message = 'Rider profile is not yet approved',
  ]);

  /// Human-readable message.
  final String message;

  @override
  String toString() => 'RiderNotApprovedError: $message';
}

/// Typed error thrown when `toggle-online` fails because the rider's
/// account is suspended (deactivated by ops).
///
/// The backend returns HTTP 403 with code `RIDER_SUSPENDED`. Going back
/// online requires an admin to unsuspend the account — this is NOT the
/// approval flow, so callers must surface it differently.
final class RiderSuspendedError implements Exception {
  /// Constructs the error with an optional [message].
  const RiderSuspendedError([this.message = 'Rider account is suspended']);

  /// Human-readable message.
  final String message;

  @override
  String toString() => 'RiderSuspendedError: $message';
}

/// Transport-level wrapper around the `/delivery` REST endpoints.
///
/// `DeliveryApi` knows how to build and decode REST calls; it does NOT
/// translate failures into rider-specific exceptions (that is
/// [DeliveryRepository]'s job) and it does NOT touch persistent
/// storage.
///
/// All paths are relative to [ApiClient.baseUrl] (which the bootstrap
/// pins to the configured Meet Commerce REST base).
class DeliveryApi {
  /// Wraps the supplied [client].
  DeliveryApi(this._client);

  final ApiClient _client;

  // ---------------------------------------------------------------------------
  // Profile & documents
  // ---------------------------------------------------------------------------

  /// Fetches the rider's profile.
  ///
  /// The live backend returns snake_case with string-typed numerics.
  /// [RiderProfile.fromJson] handles both casings and string→double
  /// conversion.
  Future<RiderProfile> getProfile() async {
    final ApiEnvelope<RiderProfile> envelope = await _client.get<RiderProfile>(
      '/delivery/profile',
      parseData: (Object? raw) => RiderProfile.fromJson(_asMap(raw, 'profile')),
    );
    return _requireData(envelope, 'profile');
  }

  /// Fetches the rider's uploaded documents.
  ///
  /// Returns the raw list from `data.documents`. The exact item shape
  /// is TBD until a document has been uploaded (task 4.1); the typed
  /// model lives with the documents feature, not here.
  Future<List<Map<String, dynamic>>> getDocuments() async {
    final ApiEnvelope<List<Map<String, dynamic>>> envelope = await _client
        .get<List<Map<String, dynamic>>>(
          '/delivery/documents',
          parseData: (Object? raw) {
            if (raw is Map) {
              final Object? docs = raw['documents'];
              if (docs is List) {
                return docs
                    .whereType<Map<dynamic, dynamic>>()
                    .map<Map<String, dynamic>>(Map<String, dynamic>.from)
                    .toList(growable: false);
              }
            }
            return const <Map<String, dynamic>>[];
          },
        );
    return envelope.data ?? const <Map<String, dynamic>>[];
  }

  /// Toggles the rider's online/offline status.
  ///
  /// The backend's eligibility gates are typed (Big Phase 6):
  /// - HTTP 403 `RIDER_NOT_APPROVED` -> [RiderNotApprovedError]
  ///   (caller routes to the approval flow).
  /// - HTTP 403 `RIDER_SUSPENDED` -> [RiderSuspendedError]
  ///   (account deactivated by ops; NOT an approval-flow problem).
  ///
  /// Any other failure is rethrown untouched — in particular a 5xx is
  /// NOT silently reinterpreted as "not approved" (a transient server
  /// error must never route an approved rider into the approval flow).
  Future<void> toggleOnline(bool isOnline) async {
    try {
      await _client.patch<Object?>(
        '/delivery/toggle-online',
        body: <String, dynamic>{'isOnline': isOnline},
        parseData: (Object? raw) => raw,
      );
    } on ApiAuthException catch (e) {
      if (e.backendCode == 'RIDER_NOT_APPROVED') {
        throw const RiderNotApprovedError();
      }
      if (e.backendCode == 'RIDER_SUSPENDED') {
        throw const RiderSuspendedError();
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Orders
  // ---------------------------------------------------------------------------

  /// Fetches the rider's current orders.
  ///
  /// The live backend returns a **bare array** under `data` (not
  /// `{ items: [] }`). An optional [status] filter is sent as the
  /// `status` query parameter (e.g. `ASSIGNED`).
  Future<List<DeliveryOrder>> getOrders({String? status}) async {
    final Map<String, dynamic>? query = status != null
        ? <String, dynamic>{'status': status}
        : null;

    final ApiEnvelope<List<DeliveryOrder>> envelope = await _client
        .get<List<DeliveryOrder>>(
          '/delivery/orders',
          queryParameters: query,
          parseData: (Object? raw) {
            if (raw is List) {
              return raw
                  .whereType<Map<dynamic, dynamic>>()
                  .map<DeliveryOrder>(
                    (Map<dynamic, dynamic> item) =>
                        DeliveryOrder.fromJson(Map<String, dynamic>.from(item)),
                  )
                  .toList(growable: false);
            }
            return const <DeliveryOrder>[];
          },
        );
    return envelope.data ?? const <DeliveryOrder>[];
  }

  /// Accepts an order offer.
  ///
  /// Returns the raw accept response map. In dev environments the
  /// response includes `deliveryOtp`; the caller must handle that
  /// field only in the `dev` flavor.
  ///
  /// The live backend requires a JSON body (even `{}`); the [patch]
  /// wrapper defaults to `{}` so this is handled automatically.
  Future<Map<String, dynamic>> acceptOrder(String orderId) async {
    final ApiEnvelope<Map<String, dynamic>> envelope = await _client
        .patch<Map<String, dynamic>>(
          '/delivery/orders/$orderId/accept',
          body: const <String, dynamic>{},
          parseData: (Object? raw) {
            if (raw is Map) {
              return Map<String, dynamic>.from(raw);
            }
            return const <String, dynamic>{};
          },
        );
    return envelope.data ?? const <String, dynamic>{};
  }

  /// Rejects an order offer with a [reason].
  ///
  /// [reason] is the uppercase wire string (`TOO_FAR`, `VEHICLE_ISSUE`,
  /// `PERSONAL_REASON`, `OTHER`). Callers typically use
  /// [RejectReason.wire] to obtain the value.
  Future<void> rejectOrder(String orderId, String reason) async {
    await _client.patch<Object?>(
      '/delivery/orders/$orderId/reject',
      body: <String, dynamic>{'reason': reason},
      parseData: (Object? raw) => raw,
    );
  }

  /// Cancels a delivery already accepted/picked up — e.g. the customer
  /// refuses the order or can't be reached at the drop location.
  ///
  /// [reason] is the uppercase wire string (`CUSTOMER_REFUSED`,
  /// `CUSTOMER_UNREACHABLE`, `CUSTOMER_NOT_HOME`, `OTHER`). Callers
  /// typically use [CancelDeliveryReason.wire] to obtain the value.
  Future<void> cancelDelivery(String orderId, String reason) async {
    await _client.patch<Object?>(
      '/delivery/orders/$orderId/cancel',
      body: <String, dynamic>{'reason': reason},
      parseData: (Object? raw) => raw,
    );
  }

  /// Verifies a scanned invoice QR pickup code.
  ///
  /// [payload] is the decoded QR content (`{token, v, sig}`) sent back
  /// verbatim as the request body — the QR carries no order/assignment
  /// id at all, so there's no `:id` in this route; the backend resolves
  /// which order this is from the token itself and returns it as
  /// `orderId` in the response. The backend re-validates the signature,
  /// token status, and rider ownership itself. Returns the price-free
  /// pickup checklist on success. Rejections surface as [ApiException]
  /// with a specific `backendCode` (`INVALID_SIGNATURE`, `TOKEN_EXPIRED`,
  /// `WRONG_RIDER`, `ALREADY_VERIFIED`, etc.) and a rider-readable
  /// `message` the caller can show verbatim.
  Future<PickupVerification> verifyScan(Map<String, dynamic> payload) async {
    final ApiEnvelope<PickupVerification> envelope = await _client
        .post<PickupVerification>(
          '/delivery/pickup-tokens/verify',
          body: payload,
          parseData: (Object? raw) =>
              PickupVerification.fromJson(_asMap(raw, 'verify-scan')),
        );
    return _requireData(envelope, 'verify-scan');
  }

  /// Re-fetches the checklist for [orderId] when this rider already
  /// scanned it successfully (token VERIFIED) but hasn't confirmed
  /// pickup yet — the recovery path for a killed/restarted app, a
  /// second device, or the checklist sheet having closed early. Cannot
  /// be used to (re-)verify a QR; the token was already claimed by the
  /// original scan and there's nothing left to claim.
  ///
  /// Throws [ApiException] with `backendCode == 'NO_PENDING_CHECKLIST'`
  /// (HTTP 404) when there's no VERIFIED-but-unconsumed token for this
  /// order under this rider — i.e. it was genuinely never scanned, or
  /// pickup was already confirmed.
  Future<PickupVerification> getPendingChecklist(String orderId) async {
    final ApiEnvelope<PickupVerification> envelope = await _client
        .get<PickupVerification>(
          '/delivery/orders/$orderId/pending-checklist',
          parseData: (Object? raw) =>
              PickupVerification.fromJson(_asMap(raw, 'pending-checklist')),
        );
    return _requireData(envelope, 'pending-checklist');
  }

  /// Marks an order as picked up from the store.
  ///
  /// The live backend requires a JSON body (even `{}`).
  Future<void> markPickedUp(String orderId) async {
    await _client.patch<Object?>(
      '/delivery/orders/$orderId/pickup',
      body: const <String, dynamic>{},
      parseData: (Object? raw) => raw,
    );
  }

  /// Marks an order as delivered — direct completion by default (no
  /// verification step). [proofPhotoUrl] and [demoMode] remain as
  /// alternate completion paths:
  /// - (none): direct completion.
  /// - [proofPhotoUrl]: proof-photo fallback (URL from [uploadProof]).
  /// - [demoMode]: dev-only demo completion. Pass `true` to enable;
  ///   `null` (default) omits the field entirely so production builds
  ///   never accidentally send `demoMode: false`.
  Future<void> markDelivered(
    String orderId, {
    String? proofPhotoUrl,
    bool? demoMode,
    double? cashCollected,
    double? upiCollected,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (proofPhotoUrl != null) body['proofPhotoUrl'] = proofPhotoUrl;
    if (demoMode != null) body['demoMode'] = demoMode;
    if (cashCollected != null) body['cashCollected'] = cashCollected;
    if (upiCollected != null) body['upiCollected'] = upiCollected;

    await _client.patch<Object?>(
      '/delivery/orders/$orderId/deliver',
      body: body,
      parseData: (Object? raw) => raw,
    );
  }

  /// Uploads a proof photo for an order.
  ///
  /// Returns the URL of the uploaded photo from `data.url`.
  Future<String> uploadProof(String orderId, File file) async {
    final FormData formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
    });

    final ApiEnvelope<String> envelope = await _client.post<String>(
      '/delivery/orders/$orderId/proof',
      body: formData,
      options: Options(contentType: 'multipart/form-data'),
      parseData: (Object? raw) {
        if (raw is Map) {
          final Object? url = raw['url'];
          if (url is String) return url;
        }
        return '';
      },
    );
    return envelope.data ?? '';
  }

  /// Updates the rider's profile fields.
  ///
  /// Only non-null parameters are sent in the request body so the
  /// caller can do a partial update (PATCH semantics). The backend
  /// returns the full updated [RiderProfile] under `data`.
  ///
  /// Editable fields: [name], [vehicleType], [vehicleNumber],
  /// [bankAccountNumber], [bankIfsc], [bankName].
  Future<RiderProfile> updateProfile({
    String? name,
    String? vehicleType,
    String? vehicleNumber,
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankName,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (vehicleType != null) body['vehicleType'] = vehicleType;
    if (vehicleNumber != null) body['vehicleNumber'] = vehicleNumber;
    if (bankAccountNumber != null)
      body['bankAccountNumber'] = bankAccountNumber;
    if (bankIfsc != null) body['bankIfsc'] = bankIfsc;
    if (bankName != null) body['bankName'] = bankName;

    final ApiEnvelope<RiderProfile> envelope = await _client
        .patch<RiderProfile>(
          '/delivery/profile',
          body: body,
          parseData: (Object? raw) =>
              RiderProfile.fromJson(_asMap(raw, 'profile')),
        );
    return _requireData(envelope, 'profile');
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  /// Updates the rider's current location.
  ///
  /// The live backend returns `{ success: true, data: null }` on
  /// success; the response body is not used.
  Future<void> updateLocation(double latitude, double longitude) async {
    await _client.patch<Object?>(
      '/delivery/location',
      body: <String, dynamic>{'latitude': latitude, 'longitude': longitude},
      parseData: (Object? raw) => raw,
    );
  }

  // ---------------------------------------------------------------------------
  // Store info
  // ---------------------------------------------------------------------------

  /// Fetches the store information.
  ///
  /// The live backend returns `lat`/`lng` as numbers (not strings) for
  /// this route. When both are 0 the store has not been configured —
  /// inspect [StoreInfo.isConfigured] before using the coordinates.
  Future<StoreInfo> getStoreInfo() async {
    final ApiEnvelope<StoreInfo> envelope = await _client.get<StoreInfo>(
      '/delivery/store-info',
      parseData: (Object? raw) => StoreInfo.fromJson(_asMap(raw, 'store-info')),
    );
    return _requireData(envelope, 'store-info');
  }

  // ---------------------------------------------------------------------------
  // Stats & earnings
  // ---------------------------------------------------------------------------

  /// Fetches the rider's performance statistics.
  Future<RiderStats> getStats() async {
    final ApiEnvelope<RiderStats> envelope = await _client.get<RiderStats>(
      '/delivery/stats',
      parseData: (Object? raw) => RiderStats.fromJson(_asMap(raw, 'stats')),
    );
    return _requireData(envelope, 'stats');
  }

  /// Fetches the rider's earnings for [period].
  Future<RiderEarnings> getEarnings(EarningsPeriod period) async {
    final ApiEnvelope<RiderEarnings> envelope = await _client
        .get<RiderEarnings>(
          '/delivery/earnings',
          queryParameters: <String, dynamic>{'period': period.wire},
          parseData: (Object? raw) =>
              RiderEarnings.fromJson(_asMap(raw, 'earnings')),
        );
    return _requireData(envelope, 'earnings');
  }

  // ---------------------------------------------------------------------------
  // Payouts & history
  // ---------------------------------------------------------------------------

  /// Fetches the rider's payout history.
  ///
  /// The live backend returns
  /// `{ items: [...], pagination: { page, total, totalPages } }` under
  /// `data`. The response is unwrapped into a typed record so callers
  /// don't have to decode the envelope themselves.
  Future<({List<Payout> items, Pagination pagination})> getPayouts({
    int page = 1,
    int limit = 20,
  }) async {
    final ApiEnvelope<({List<Payout> items, Pagination pagination})> envelope =
        await _client.get(
          '/delivery/payouts',
          queryParameters: <String, dynamic>{'page': page, 'limit': limit},
          parseData: (Object? raw) {
            if (raw is Map) {
              final Object? rawItems = raw['items'];
              final List<Payout> items = rawItems is List
                  ? rawItems
                        .whereType<Map<dynamic, dynamic>>()
                        .map<Payout>(
                          (Map<dynamic, dynamic> item) =>
                              Payout.fromJson(Map<String, dynamic>.from(item)),
                        )
                        .toList(growable: false)
                  : const <Payout>[];

              final Object? rawPagination = raw['pagination'];
              final Pagination pagination = rawPagination is Map
                  ? Pagination.fromJson(
                      Map<String, dynamic>.from(rawPagination),
                    )
                  : const Pagination(page: 1, totalPages: 1, total: 0);

              return (items: items, pagination: pagination);
            }
            return (
              items: const <Payout>[],
              pagination: const Pagination(page: 1, totalPages: 1, total: 0),
            );
          },
        );
    return envelope.data ??
        (
          items: const <Payout>[],
          pagination: const Pagination(page: 1, totalPages: 1, total: 0),
        );
  }

  /// Fetches the rider's delivery history.
  ///
  /// The live backend returns `{ orders: [...], total: 0 }` under
  /// `data` (note: not the same envelope as payouts).
  Future<({List<DeliveryHistoryEntry> orders, int total})> getHistory({
    int page = 1,
    int limit = 20,
  }) async {
    final ApiEnvelope<({List<DeliveryHistoryEntry> orders, int total})>
    envelope = await _client.get(
      '/delivery/history',
      queryParameters: <String, dynamic>{'page': page, 'limit': limit},
      parseData: (Object? raw) {
        if (raw is Map) {
          final Object? rawOrders = raw['orders'];
          final List<DeliveryHistoryEntry> orders = rawOrders is List
              ? rawOrders
                    .whereType<Map<dynamic, dynamic>>()
                    .map<DeliveryHistoryEntry>(
                      (Map<dynamic, dynamic> item) =>
                          DeliveryHistoryEntry.fromJson(
                            Map<String, dynamic>.from(item),
                          ),
                    )
                    .toList(growable: false)
              : const <DeliveryHistoryEntry>[];

          final int total = _readInt(raw['total']);
          return (orders: orders, total: total);
        }
        return (orders: const <DeliveryHistoryEntry>[], total: 0);
      },
    );
    return envelope.data ?? (orders: const <DeliveryHistoryEntry>[], total: 0);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _asMap(Object? raw, String routeName) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    throw DioException(
      requestOptions: RequestOptions(path: '/delivery/$routeName'),
      type: DioExceptionType.badResponse,
      message: '$routeName returned malformed payload: $raw',
    );
  }

  static T _requireData<T>(ApiEnvelope<T> envelope, String routeName) {
    final T? data = envelope.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/delivery/$routeName'),
        type: DioExceptionType.badResponse,
        message: '$routeName returned no data',
      );
    }
    return data;
  }

  static int _readInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
