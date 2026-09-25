import 'package:flutter/foundation.dart';

import '../data/order_parser.dart';

/// A single payout record returned inside `/delivery/payouts.items`.
///
/// The exact backend shape is still being verified — the live `items`
/// array is empty for the seed rider — so the parser is intentionally
/// lenient and falls back to the `Map<String, dynamic>` raw form via
/// [raw] for fields we don't know about yet.
@immutable
class Payout {
  /// Constructs a payout record explicitly.
  const Payout({
    required this.id,
    required this.amount,
    required this.status,
    this.createdAt,
    this.processedAt,
    this.referenceId,
    this.method,
    this.raw = const <String, dynamic>{},
  });

  /// Lenient parser. Tolerates both snake_case and camelCase keys, and
  /// numeric-string amounts.
  factory Payout.fromJson(Map<String, dynamic> j) {
    return Payout(
      id: OrderParser.readString(j, 'id'),
      amount: OrderParser.readMoney(j, 'amount'),
      status: OrderParser.readString(
        j,
        'status',
        null,
        'PENDING',
      ).toUpperCase(),
      createdAt:
          OrderParser.readStringOpt(j, 'createdAt', 'created_at') ??
          OrderParser.readStringOpt(j, 'date'),
      processedAt: OrderParser.readStringOpt(j, 'processedAt', 'processed_at'),
      referenceId:
          OrderParser.readStringOpt(j, 'referenceId', 'reference_id') ??
          OrderParser.readStringOpt(j, 'utr'),
      method: OrderParser.readStringOpt(j, 'method'),
      raw: Map<String, dynamic>.unmodifiable(j),
    );
  }

  /// Serialises to camelCase JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'amount': amount,
    'status': status,
    if (createdAt != null) 'createdAt': createdAt,
    if (processedAt != null) 'processedAt': processedAt,
    if (referenceId != null) 'referenceId': referenceId,
    if (method != null) 'method': method,
  };

  /// Payout identifier.
  final String id;

  /// Payout amount, rounded to 2 decimal places.
  final double amount;

  /// Status (e.g. `PENDING`, `PAID`, `FAILED`). Always uppercase.
  final String status;

  /// ISO timestamp when the payout was created. Null when absent.
  final String? createdAt;

  /// ISO timestamp when the payout was processed. Null when pending.
  final String? processedAt;

  /// Bank reference / UTR. Null until the payout is processed.
  final String? referenceId;

  /// Payment method (e.g. `BANK_TRANSFER`, `UPI`). Optional.
  final String? method;

  /// The raw JSON map this payout was parsed from.
  ///
  /// Exposed read-only so the UI can render fields the typed model
  /// doesn't enumerate yet without re-parsing.
  final Map<String, dynamic> raw;

  @override
  bool operator ==(Object other) {
    return other is Payout &&
        other.id == id &&
        other.amount == amount &&
        other.status == status &&
        other.createdAt == createdAt &&
        other.processedAt == processedAt &&
        other.referenceId == referenceId &&
        other.method == method;
  }

  @override
  int get hashCode => Object.hash(
    id,
    amount,
    status,
    createdAt,
    processedAt,
    referenceId,
    method,
  );

  @override
  String toString() => 'Payout(id=$id, amount=$amount, status=$status)';
}
