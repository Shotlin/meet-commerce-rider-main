import 'package:flutter/foundation.dart';

import '../data/order_parser.dart';

/// A single line item in a delivery order.
///
/// Accepts both camelCase and snake_case field names, and both string
/// and numeric values for price fields (R19.1, R28.4). Money fields are
/// rounded to 2 decimal places by [OrderParser.readMoney].
@immutable
class DeliveryItem {
  /// Constructs a delivery item explicitly.
  const DeliveryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  /// Lenient parser. Accepts `productName`/`name`, `qty`/`quantity`,
  /// `unit_price`/`unitPrice`, `total_price`/`totalPrice`. Numeric
  /// fields tolerate string-encoded values from the live backend.
  factory DeliveryItem.fromJson(Map<String, dynamic> j) {
    // `name` falls back to `productName` when the canonical key is
    // missing — preserve that fallback because some live order payloads
    // historically used `productName`.
    final String name = OrderParser.readString(j, 'name').isNotEmpty
        ? OrderParser.readString(j, 'name')
        : OrderParser.readString(j, 'productName');
    final int quantity = OrderParser.readIntOpt(j, 'quantity', 'qty') ?? 0;

    return DeliveryItem(
      id: OrderParser.readString(j, 'id'),
      name: name,
      quantity: quantity,
      unitPrice: OrderParser.readMoney(j, 'unitPrice', 'unit_price'),
      totalPrice: OrderParser.readMoney(j, 'totalPrice', 'total_price'),
    );
  }

  /// Serialises to camelCase JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'totalPrice': totalPrice,
  };

  /// Returns a copy with the supplied fields replaced.
  DeliveryItem copyWith({
    String? id,
    String? name,
    int? quantity,
    double? unitPrice,
    double? totalPrice,
  }) {
    return DeliveryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
    );
  }

  /// Item identifier.
  final String id;

  /// Product name.
  final String name;

  /// Number of units.
  final int quantity;

  /// Price per unit, rounded to 2 decimal places.
  final double unitPrice;

  /// Total price for this line (quantity × unitPrice), rounded to 2 dp.
  final double totalPrice;

  @override
  bool operator ==(Object other) {
    return other is DeliveryItem &&
        other.id == id &&
        other.name == name &&
        other.quantity == quantity &&
        other.unitPrice == unitPrice &&
        other.totalPrice == totalPrice;
  }

  @override
  int get hashCode => Object.hash(id, name, quantity, unitPrice, totalPrice);

  @override
  String toString() =>
      'DeliveryItem(id=$id, name=$name, qty=$quantity, '
      'unitPrice=$unitPrice, totalPrice=$totalPrice)';
}
