/// Exceptions thrown by the delivery domain layer.
///
/// `OrderParseException` and `UnknownAssignmentStatusException` are
/// defined here. `InvalidCoordinateException` is defined in
/// `core/utils/coordinate.dart` and re-exported from this file so
/// existing imports keep working — the delivery layer is the one that
/// catches it most often, but the invariant lives next to the
/// [Coordinate] value object so the location subsystem can share it.

export '../../../core/utils/coordinate.dart' show InvalidCoordinateException;

/// Thrown when a required field is missing or cannot be parsed from a
/// delivery order JSON payload.
///
/// Example: an order payload missing `orderId` produces
/// `OrderParseException('orderId')`.
final class OrderParseException implements Exception {
  /// Constructs the exception with the offending [field] name.
  const OrderParseException(this.field);

  /// The name of the field that was missing or malformed.
  final String field;

  @override
  String toString() =>
      'OrderParseException: required field "$field" is missing or invalid';
}

/// Thrown when an `AssignmentStatus` wire value is not one of the
/// recognised strings (`ASSIGNED`, `ACCEPTED`, `IN_TRANSIT`,
/// `DELIVERED`, `CANCELLED`).
final class UnknownAssignmentStatusException implements Exception {
  /// Constructs the exception with the unrecognised [value].
  const UnknownAssignmentStatusException(this.value);

  /// The unrecognised wire string.
  final String value;

  @override
  String toString() =>
      'UnknownAssignmentStatusException: unknown assignment status "$value"';
}
