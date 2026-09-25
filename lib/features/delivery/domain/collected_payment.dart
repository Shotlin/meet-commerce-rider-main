import 'package:flutter/foundation.dart';

/// Cash-vs-UPI split the rider records for a Cash on Delivery order at the
/// payment-collection step, before completing the OTP/proof delivery flow.
///
/// Returned by `showCollectPaymentSheet` — `null` from that call means the
/// rider dismissed the sheet without confirming (delivery should not
/// proceed).
@immutable
class CollectedPayment {
  /// Constructs a collected-payment split.
  const CollectedPayment({
    required this.cashCollected,
    required this.upiCollected,
  });

  /// Amount the rider recorded as collected in cash.
  final double cashCollected;

  /// Amount the rider recorded as collected via the UPI QR.
  final double upiCollected;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CollectedPayment) return false;
    return other.cashCollected == cashCollected &&
        other.upiCollected == upiCollected;
  }

  @override
  int get hashCode => Object.hash(cashCollected, upiCollected);
}
