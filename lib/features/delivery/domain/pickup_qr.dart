import 'package:flutter/foundation.dart';

/// The FreshCuts order code printed on the invoice stuck to every order bag
/// (`FRESHCUTS-ORDER|<orderNumber>|<orderId>`) — the same code the
/// customer app shows for the order. The rider scans it at the store to
/// prove they are collecting the right bag.
@immutable
class ParsedOrderQr {
  /// Constructs a parsed order code.
  const ParsedOrderQr({required this.orderNumber, required this.orderId});

  /// Human-readable order number, e.g. `FC-KOL-20260928-0001`.
  final String orderNumber;

  /// Order UUID (lower-cased).
  final String orderId;

  @override
  bool operator ==(Object other) =>
      other is ParsedOrderQr &&
      other.orderNumber == orderNumber &&
      other.orderId == orderId;

  @override
  int get hashCode => Object.hash(orderNumber, orderId);
}

/// Prefix every FreshCuts order code starts with.
const String kOrderQrPrefix = 'FRESHCUTS-ORDER';

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Parses a scanned QR string. Returns null for anything that is not a
/// well-formed FreshCuts order code (wrong prefix, missing parts, or an id
/// that is not a UUID), so the scanner can say "not a FreshCuts code"
/// without a network call.
ParsedOrderQr? parseOrderQr(String? raw) {
  if (raw == null) return null;
  final List<String> parts = raw.trim().split('|');
  if (parts.length != 3 || parts[0] != kOrderQrPrefix) return null;
  final String orderNumber = parts[1].trim();
  final String orderId = parts[2].trim();
  if (orderNumber.isEmpty || !_uuid.hasMatch(orderId)) return null;
  return ParsedOrderQr(
    orderNumber: orderNumber,
    orderId: orderId.toLowerCase(),
  );
}
