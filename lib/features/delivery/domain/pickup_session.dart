import 'package:flutter/foundation.dart';

import '../data/order_parser.dart';

/// Client-side, session-local status for the rider's single order in
/// the current pickup-at-store session. Deliberately NOT part of
/// [DeliveryOrder]'s wire representation — the backend has no concept
/// of "needs scan" vs. "verified," only the QR pickup token's own
/// lifecycle (ACTIVE/VERIFIED/CONSUMED/REVOKED/EXPIRED). This enum is
/// purely the app's local mirror of "how far has this rider gotten
/// through pickup verification," reset each time a new pickup session
/// starts.
enum PickupScanStatus {
  /// Assigned to this rider but not yet scanned this session.
  needsScan,

  /// Scanned and verified via `verify-scan`; checklist confirmed, waiting
  /// on "Confirm Pickup."
  verified,

  /// Pickup confirmed (`markPickedUp` succeeded) — ready for delivery.
  pickedUp,
}

/// One line item on a pickup checklist — deliberately carries no price
/// field. Parsed from `verify-scan`'s response, which never returns one
/// (see `delivery.service.js#verifyScan` / `delivery.repository.js#getPickupChecklist`
/// on the backend — price/subtotal/tax/discount are absent from the SQL
/// SELECT itself, not merely hidden here).
@immutable
class PickupChecklistItem {
  const PickupChecklistItem({
    required this.name,
    required this.quantity,
    required this.unit,
    this.image,
    this.variant,
  });

  factory PickupChecklistItem.fromJson(Map<String, dynamic> json) {
    return PickupChecklistItem(
      name: OrderParser.readString(json, 'name'),
      quantity: OrderParser.readInt(json, 'quantity'),
      unit: OrderParser.readStringOpt(json, 'unit') ?? '',
      image: OrderParser.readStringOpt(json, 'image'),
      variant: OrderParser.readStringOpt(json, 'variant'),
    );
  }

  final String name;
  final int quantity;
  final String unit;
  final String? image;
  final String? variant;
}

/// The result of a successful `verify-scan` call — everything the rider
/// needs to see at pickup, and nothing financial. Kept as a standalone
/// type rather than merged into [DeliveryOrder] since it's a one-shot scan
/// result, not the order's persistent shape.
///
/// [orderId] is the order this token resolved to — the QR itself carries
/// no order reference (see backend `qrToken.js`), so callers only learn
/// which order they scanned from this response, not from the QR content.
@immutable
class PickupVerification {
  const PickupVerification({
    required this.orderId,
    required this.orderNumber,
    required this.customerName,
    required this.customerPhone,
    required this.addressLine,
    required this.lat,
    required this.lng,
    required this.deliveryNotes,
    required this.deliveryInstructions,
    required this.items,
  });

  factory PickupVerification.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> address =
        OrderParser.readMap(json, 'deliveryAddress') ??
        const <String, dynamic>{};
    final String addressLine = <String?>[
      OrderParser.readStringOpt(address, 'label'),
      OrderParser.readStringOpt(address, 'addressLine1', 'address_line1'),
      OrderParser.readStringOpt(address, 'addressLine2', 'address_line2'),
      OrderParser.readStringOpt(address, 'landmark'),
      OrderParser.readStringOpt(address, 'city'),
      OrderParser.readStringOpt(address, 'pincode'),
    ].whereType<String>().where((String s) => s.trim().isNotEmpty).join(', ');

    return PickupVerification(
      orderId: OrderParser.readString(json, 'orderId'),
      orderNumber: OrderParser.readString(json, 'orderNumber'),
      customerName:
          OrderParser.readStringOpt(json, 'customerName') ?? 'Customer',
      customerPhone: OrderParser.readStringOpt(json, 'customerPhone') ?? '',
      addressLine: addressLine,
      lat: OrderParser.readDoubleOpt(json, 'lat'),
      lng: OrderParser.readDoubleOpt(json, 'lng'),
      deliveryNotes: OrderParser.readStringOpt(json, 'deliveryNotes'),
      deliveryInstructions: OrderParser.readStringOpt(
        json,
        'deliveryInstructions',
      ),
      items: OrderParser.readMapList(
        json,
        'items',
      ).map(PickupChecklistItem.fromJson).toList(growable: false),
    );
  }

  final String orderId;
  final String orderNumber;
  final String customerName;
  final String customerPhone;
  final String addressLine;
  final double? lat;
  final double? lng;
  final String? deliveryNotes;
  final String? deliveryInstructions;
  final List<PickupChecklistItem> items;
}
