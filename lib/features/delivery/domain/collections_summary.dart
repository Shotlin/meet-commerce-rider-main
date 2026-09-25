import 'package:flutter/foundation.dart';

import '../data/order_parser.dart';

/// The rider cash ledger roll-up from
/// `GET /delivery/collections/summary` (Big Phase 14).
///
/// - [cashInHand] — cash collected but not yet handed over (the home
///   tile's value; equal to [pendingHandover] by definition).
/// - [cashSettled] — cash already reconciled by an admin settlement.
/// - [upiCollectedTotal] — money collected through the business UPI QR
///   (goes straight to the business account; nothing to hand over).
@immutable
class CollectionsSummary {
  /// Constructs the summary explicitly.
  const CollectionsSummary({
    required this.collectedToday,
    required this.cashCollectedTotal,
    required this.upiCollectedTotal,
    required this.cashSettled,
    required this.cashInHand,
    required this.pendingHandover,
  });

  /// Parses the backend's camelCase response (lenient like the other
  /// parsers — numbers may arrive string-encoded).
  factory CollectionsSummary.fromJson(Map<String, dynamic> j) {
    double read(String camel, String snake) =>
        OrderParser.readDouble(j, camel, snake);
    return CollectionsSummary(
      collectedToday: read('collectedToday', 'collected_today'),
      cashCollectedTotal: read('cashCollectedTotal', 'cash_collected_total'),
      upiCollectedTotal: read('upiCollectedTotal', 'upi_collected_total'),
      cashSettled: read('cashSettled', 'cash_settled'),
      cashInHand: read('cashInHand', 'cash_in_hand'),
      pendingHandover: read('pendingHandover', 'pending_handover'),
    );
  }

  final double collectedToday;
  final double cashCollectedTotal;
  final double upiCollectedTotal;
  final double cashSettled;
  final double cashInHand;
  final double pendingHandover;

  @override
  bool operator ==(Object other) {
    return other is CollectionsSummary &&
        other.collectedToday == collectedToday &&
        other.cashCollectedTotal == cashCollectedTotal &&
        other.upiCollectedTotal == upiCollectedTotal &&
        other.cashSettled == cashSettled &&
        other.cashInHand == cashInHand &&
        other.pendingHandover == pendingHandover;
  }

  @override
  int get hashCode => Object.hash(
    collectedToday,
    cashCollectedTotal,
    upiCollectedTotal,
    cashSettled,
    cashInHand,
    pendingHandover,
  );
}
