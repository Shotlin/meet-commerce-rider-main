import 'package:flutter/foundation.dart';

import '../../../core/maps/geo.dart';
import '../../../core/maps/geo_point.dart';
import '../data/order_parser.dart';
import 'assignment_status.dart';
import 'delivery_address.dart';
import 'delivery_item.dart';
import 'order_parse_exception.dart';

/// A delivery assignment as returned by `/delivery/orders` and related
/// endpoints.
///
/// The parser is deliberately lenient (R19): it accepts both
/// snake_case and camelCase field names (R19.1), prefers camelCase
/// when both are present (R19.2), and converts numeric strings to
/// doubles for money / coordinate fields (R28.4).
///
/// Required fields (`orderId`, `assignmentStatus`) throw
/// [OrderParseException] when missing (R19.4). Unknown
/// `assignmentStatus` values throw [UnknownAssignmentStatusException]
/// (R19.5). Out-of-range coordinates anywhere inside the customer or
/// store address throw [InvalidCoordinateException] (R28.3).
@immutable
class DeliveryOrder {
  /// Constructs a delivery order explicitly.
  const DeliveryOrder({
    required this.orderId,
    this.assignmentId,
    required this.orderNumber,
    required this.assignmentStatus,
    this.orderStatus,
    required this.totalAmount,
    required this.paymentMethod,
    required this.riderEarning,
    this.estimatedDistance,
    required this.estimatedDuration,
    required this.customerAddress,
    required this.storeAddress,
    required this.items,
    this.deliveryMode,
    this.quickDeliverySelected = false,
    this.scheduledSlotStart,
    this.createdAt,
  });

  /// Lenient parser.
  ///
  /// Accepts both snake_case and camelCase field names. Throws
  /// [OrderParseException] for missing required fields,
  /// [UnknownAssignmentStatusException] for unknown statuses, and
  /// [InvalidCoordinateException] for out-of-range coordinates inside
  /// either nested address.
  factory DeliveryOrder.fromJson(Map<String, dynamic> j) {
    // Required: orderId
    final String? rawOrderId = OrderParser.readStringOpt(
      j,
      'orderId',
      'order_id',
    );
    if (rawOrderId == null || rawOrderId.isEmpty) {
      throw const OrderParseException('orderId');
    }

    // Required: assignmentStatus
    final String? rawStatus = OrderParser.readStringOpt(
      j,
      'assignmentStatus',
      'assignment_status',
    );
    if (rawStatus == null || rawStatus.isEmpty) {
      throw const OrderParseException('assignmentStatus');
    }
    final AssignmentStatus assignmentStatus = AssignmentStatus.parse(rawStatus);

    // Required: customerAddress and storeAddress (object shape).
    final Map<String, dynamic>? rawCustomer = OrderParser.readMap(
      j,
      'customerAddress',
      'customer_address',
    );
    if (rawCustomer == null) {
      throw const OrderParseException('customerAddress');
    }
    final Map<String, dynamic>? rawStore = OrderParser.readMap(
      j,
      'storeAddress',
      'store_address',
    );
    if (rawStore == null) {
      throw const OrderParseException('storeAddress');
    }

    return DeliveryOrder(
      orderId: rawOrderId,
      assignmentId: OrderParser.readStringOpt(
        j,
        'assignmentId',
        'assignment_id',
      ),
      orderNumber:
          OrderParser.readStringOpt(
            j,
            'orderNumber',
            'order_number',
          )?.takeUnlessEmpty() ??
          rawOrderId,
      assignmentStatus: assignmentStatus,
      orderStatus: OrderParser.readStringOpt(j, 'orderStatus', 'order_status'),
      totalAmount: OrderParser.readMoney(j, 'totalAmount', 'total_amount'),
      paymentMethod: OrderParser.readString(
        j,
        'paymentMethod',
        'payment_method',
      ),
      riderEarning: OrderParser.readMoney(j, 'riderEarning', 'rider_earning'),
      estimatedDistance: OrderParser.readDoubleOpt(
        j,
        'estimatedDistance',
        'estimated_distance',
      ),
      estimatedDuration: OrderParser.readInt(
        j,
        'estimatedDuration',
        'estimated_duration',
      ),
      customerAddress: DeliveryAddress.fromJson(rawCustomer),
      storeAddress: DeliveryAddress.fromJson(rawStore),
      items: OrderParser.readMapList(
        j,
        'items',
      ).map<DeliveryItem>(DeliveryItem.fromJson).toList(growable: false),
      deliveryMode: OrderParser.readStringOpt(
        j,
        'deliveryMode',
        'delivery_mode',
      ),
      quickDeliverySelected: OrderParser.readBool(
        j,
        'quickDeliverySelected',
        'quick_delivery_selected',
      ),
      scheduledSlotStart: _readDateTimeOpt(
        j,
        'scheduledSlotStart',
        'scheduled_slot_start',
      ),
      createdAt: _readDateTimeOpt(j, 'createdAt', 'created_at'),
    );
  }

  static DateTime? _readDateTimeOpt(
    Map<String, dynamic> j,
    String camelKey,
    String snakeKey,
  ) {
    final String? raw = OrderParser.readStringOpt(j, camelKey, snakeKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Serialises to camelCase JSON (R19.3 round-trip).
  Map<String, dynamic> toJson() => <String, dynamic>{
    'orderId': orderId,
    if (assignmentId != null) 'assignmentId': assignmentId,
    'orderNumber': orderNumber,
    'assignmentStatus': assignmentStatus.wire,
    if (orderStatus != null) 'orderStatus': orderStatus,
    'totalAmount': totalAmount,
    'paymentMethod': paymentMethod,
    'riderEarning': riderEarning,
    if (estimatedDistance != null) 'estimatedDistance': estimatedDistance,
    'estimatedDuration': estimatedDuration,
    'customerAddress': customerAddress.toJson(),
    'storeAddress': storeAddress.toJson(),
    'items': items.map((DeliveryItem i) => i.toJson()).toList(),
    if (deliveryMode != null) 'deliveryMode': deliveryMode,
    'quickDeliverySelected': quickDeliverySelected,
    if (scheduledSlotStart != null)
      'scheduledSlotStart': scheduledSlotStart!.toIso8601String(),
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  /// Returns a copy with the supplied fields replaced.
  DeliveryOrder copyWith({
    String? orderId,
    String? assignmentId,
    String? orderNumber,
    AssignmentStatus? assignmentStatus,
    String? orderStatus,
    double? totalAmount,
    String? paymentMethod,
    double? riderEarning,
    double? estimatedDistance,
    int? estimatedDuration,
    DeliveryAddress? customerAddress,
    DeliveryAddress? storeAddress,
    List<DeliveryItem>? items,
    String? deliveryMode,
    bool? quickDeliverySelected,
    DateTime? scheduledSlotStart,
    DateTime? createdAt,
  }) {
    return DeliveryOrder(
      orderId: orderId ?? this.orderId,
      assignmentId: assignmentId ?? this.assignmentId,
      orderNumber: orderNumber ?? this.orderNumber,
      assignmentStatus: assignmentStatus ?? this.assignmentStatus,
      orderStatus: orderStatus ?? this.orderStatus,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      riderEarning: riderEarning ?? this.riderEarning,
      estimatedDistance: estimatedDistance ?? this.estimatedDistance,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      customerAddress: customerAddress ?? this.customerAddress,
      storeAddress: storeAddress ?? this.storeAddress,
      items: items ?? this.items,
      deliveryMode: deliveryMode ?? this.deliveryMode,
      quickDeliverySelected:
          quickDeliverySelected ?? this.quickDeliverySelected,
      scheduledSlotStart: scheduledSlotStart ?? this.scheduledSlotStart,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Order identifier (UUID).
  final String orderId;

  /// Assignment identifier. May be null for orders returned without an
  /// explicit assignment record.
  final String? assignmentId;

  /// Human-readable order number (e.g. `ORD-1234`).
  final String orderNumber;

  /// Current assignment lifecycle state.
  final AssignmentStatus assignmentStatus;

  /// Order status string from the backend (e.g. `CONFIRMED`, `PACKED`).
  final String? orderStatus;

  /// Total order amount, rounded to 2 decimal places.
  final double totalAmount;

  /// Payment method (e.g. `ONLINE`, `COD`).
  final String paymentMethod;

  /// Rider's earning for this delivery, rounded to 2 decimal places.
  final double riderEarning;

  /// Estimated delivery distance in kilometres. Null when not provided.
  final double? estimatedDistance;

  /// Estimated delivery duration in minutes.
  final int estimatedDuration;

  /// Customer delivery address.
  final DeliveryAddress customerAddress;

  /// Store pickup address.
  final DeliveryAddress storeAddress;

  /// Line items in the order.
  final List<DeliveryItem> items;

  /// `ASAP` or `SCHEDULED`. Null if the backend response didn't include it
  /// (older cached data) — treated as ASAP for sequencing purposes.
  final String? deliveryMode;

  /// Whether the customer paid the Quick Delivery ("Express") surcharge —
  /// the highest-priority tier in multi-stop sequencing (item 8/9).
  final bool quickDeliverySelected;

  /// Start of the customer's promised delivery window, for `SCHEDULED`
  /// orders. Null for `ASAP` orders, which have no fixed window.
  final DateTime? scheduledSlotStart;

  /// When the order was placed — the fallback sequencing key for `ASAP`
  /// orders (whichever has been waiting longest goes first).
  final DateTime? createdAt;

  /// Multi-stop delivery sequencing (item 8/9): Quick Delivery ("Express")
  /// orders always come before everything else. Within the same tier,
  /// whichever order has the earlier "promised" moment goes first — a
  /// scheduled order's window start if it has one, otherwise when the
  /// order was placed (so a `SCHEDULED` order with no parsed slot still
  /// sequences sanely instead of sorting as "no promise at all").
  /// Orders with neither timestamp sort last within their tier, stably.
  static int compareDeliveryPriority(DeliveryOrder a, DeliveryOrder b) {
    final int tierCompare = _priorityTier(a).compareTo(_priorityTier(b));
    if (tierCompare != 0) return tierCompare;

    final DateTime? aKey = a.scheduledSlotStart ?? a.createdAt;
    final DateTime? bKey = b.scheduledSlotStart ?? b.createdAt;
    if (aKey == null && bKey == null) return 0;
    if (aKey == null) return 1;
    if (bKey == null) return -1;
    return aKey.compareTo(bKey);
  }

  static int _priorityTier(DeliveryOrder order) =>
      order.quickDeliverySelected ? 0 : 1;

  /// This order's customer location as a [GeoPoint], or `null` when it
  /// hasn't been geocoded yet.
  GeoPoint? get customerPoint {
    final double? lat = customerAddress.lat;
    final double? lng = customerAddress.lng;
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }

  /// Great-circle distance from [from] to this order's customer
  /// location, or `null` when the customer's coordinates aren't known
  /// yet (e.g. address not geocoded).
  double? distanceFromMeters(GeoPoint from) {
    final GeoPoint? point = customerPoint;
    if (point == null) return null;
    return Geo.distanceMeters(from, point);
  }

  /// Real multi-stop route sequencing (item 8/9): a greedy
  /// nearest-neighbor path, not a single flat sort. The first stop is
  /// whichever [orders] is closest to [riderPosition]; the *second* stop
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DeliveryOrder) return false;
    if (other.orderId != orderId) return false;
    if (other.assignmentId != assignmentId) return false;
    if (other.orderNumber != orderNumber) return false;
    if (other.assignmentStatus != assignmentStatus) return false;
    if (other.orderStatus != orderStatus) return false;
    if (other.totalAmount != totalAmount) return false;
    if (other.paymentMethod != paymentMethod) return false;
    if (other.riderEarning != riderEarning) return false;
    if (other.estimatedDistance != estimatedDistance) return false;
    if (other.estimatedDuration != estimatedDuration) return false;
    if (other.customerAddress != customerAddress) return false;
    if (other.storeAddress != storeAddress) return false;
    if (other.deliveryMode != deliveryMode) return false;
    if (other.quickDeliverySelected != quickDeliverySelected) return false;
    if (other.scheduledSlotStart != scheduledSlotStart) return false;
    if (other.createdAt != createdAt) return false;
    if (other.items.length != items.length) return false;
    for (int i = 0; i < items.length; i++) {
      if (other.items[i] != items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    orderId,
    assignmentId,
    orderNumber,
    assignmentStatus,
    orderStatus,
    totalAmount,
    paymentMethod,
    riderEarning,
    estimatedDistance,
    estimatedDuration,
    customerAddress,
    storeAddress,
    deliveryMode,
    quickDeliverySelected,
    scheduledSlotStart,
    createdAt,
    Object.hashAll(items),
  );

  @override
  String toString() =>
      'DeliveryOrder(orderId=$orderId, status=${assignmentStatus.wire}, '
      'earning=$riderEarning)';
}

extension on String {
  /// Returns this string when non-empty, else null. Used to distinguish
  /// "missing or empty" from "present with content" without re-running
  /// the parser.
  String? takeUnlessEmpty() => isEmpty ? null : this;
}
