import 'package:flutter/foundation.dart';

import '../data/order_parser.dart';

/// A row in the `/delivery/history` response.
///
/// The exact backend shape is still being verified — the live `orders`
/// array is empty for the seed rider — so this model captures the
/// fields we know we'll render (id, order number, status, earnings,
/// completion timestamp, customer area) and exposes the [raw] map for
/// any extra fields the screen wants to surface.
@immutable
class DeliveryHistoryEntry {
  /// Constructs a history entry explicitly.
  const DeliveryHistoryEntry({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.earnings,
    this.completedAt,
    this.customerArea,
    this.raw = const <String, dynamic>{},
  });

  /// Lenient parser. Accepts both casings and tolerates string-typed
  /// money amounts. Falls back through several aliases for the amount
  /// field because earlier backend prototypes used `delivery_fee`,
  /// `earnings`, and `amount` interchangeably.
  factory DeliveryHistoryEntry.fromJson(Map<String, dynamic> j) {
    final double earnings =
        OrderParser.readMoneyOpt(j, 'riderEarning', 'rider_earning') ??
        OrderParser.readMoneyOpt(j, 'deliveryFee', 'delivery_fee') ??
        OrderParser.readMoneyOpt(j, 'earnings') ??
        OrderParser.readMoney(j, 'amount');

    // Top-level `customerArea` (or its snake_case alias) takes
    // precedence over the nested-address extraction so the round-trip
    // through [toJson] (which emits the flat field) is lossless.
    final String? customerArea =
        OrderParser.readStringOpt(j, 'customerArea', 'customer_area') ??
        _extractArea(j);

    return DeliveryHistoryEntry(
      id: OrderParser.readString(j, 'id', 'order_id'),
      orderNumber:
          OrderParser.readStringOpt(j, 'orderNumber', 'order_number') ??
          OrderParser.readString(j, 'id', 'order_id'),
      status: OrderParser.readString(
        j,
        'status',
        null,
        'DELIVERED',
      ).toUpperCase(),
      earnings: earnings,
      completedAt:
          OrderParser.readStringOpt(j, 'completedAt', 'completed_at') ??
          OrderParser.readStringOpt(j, 'createdAt', 'created_at') ??
          OrderParser.readStringOpt(j, 'date'),
      customerArea: customerArea,
      raw: Map<String, dynamic>.unmodifiable(j),
    );
  }

  /// Serialises to camelCase JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'orderNumber': orderNumber,
    'status': status,
    'earnings': earnings,
    if (completedAt != null) 'completedAt': completedAt,
    if (customerArea != null) 'customerArea': customerArea,
  };

  /// Order identifier.
  final String id;

  /// Human-readable order number.
  final String orderNumber;

  /// Final assignment status (`DELIVERED`, `CANCELLED`, etc.). Always
  /// uppercase.
  final String status;

  /// Rider earnings for the delivery, rounded to 2 decimal places.
  final double earnings;

  /// ISO timestamp at which the delivery was completed. Null when the
  /// payload omits it.
  final String? completedAt;

  /// Best-effort customer area / locality string for list display.
  /// Null when the payload doesn't include an address block.
  final String? customerArea;

  /// The raw JSON map this entry was parsed from. Exposed read-only.
  final Map<String, dynamic> raw;

  /// Tries to extract a human-readable area string from a nested
  /// `customerAddress` / `delivery_address` object. Returns null when
  /// no recognisable area field is present.
  static String? _extractArea(Map<String, dynamic> j) {
    final Map<String, dynamic>? address =
        OrderParser.readMap(j, 'customerAddress', 'customer_address') ??
        OrderParser.readMap(j, 'deliveryAddress', 'delivery_address') ??
        OrderParser.readMap(j, 'address');
    if (address == null) return null;

    final String? area =
        OrderParser.readStringOpt(address, 'area') ??
        OrderParser.readStringOpt(address, 'locality') ??
        OrderParser.readStringOpt(address, 'city') ??
        OrderParser.readStringOpt(address, 'address');
    if (area == null || area.isEmpty) return null;
    return area;
  }

  @override
  bool operator ==(Object other) {
    return other is DeliveryHistoryEntry &&
        other.id == id &&
        other.orderNumber == orderNumber &&
        other.status == status &&
        other.earnings == earnings &&
        other.completedAt == completedAt &&
        other.customerArea == customerArea;
  }

  @override
  int get hashCode =>
      Object.hash(id, orderNumber, status, earnings, completedAt, customerArea);

  @override
  String toString() =>
      'DeliveryHistoryEntry(id=$id, status=$status, earnings=$earnings)';
}
