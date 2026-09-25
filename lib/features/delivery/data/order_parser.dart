/// Centralised lenient field-read helpers for the delivery domain
/// `fromJson` factories.
///
/// The live Meet Commerce backend mixes shapes across routes:
///
/// - **Auth** routes use camelCase (`accessToken`, `isVerified`).
/// - **Profile** uses snake_case with **string-typed** numerics
///   (`is_approved`, `current_lat: "22.57260000"`,
///   `commission_rate: "15.00"`).
/// - **Stats / earnings / store-info** use camelCase with numeric
///   numerics.
/// - **Orders** are returned as a bare array under `data`.
/// - Pagination wrappers differ per route.
///
/// `OrderParser` exposes one helper per shape we need to read:
/// `readDouble`, `readDoubleOpt`, `readMoney`, `readMoneyOpt`,
/// `readInt`, `readIntOpt`, `readString`, `readStringOpt`, `readBool`,
/// `readBoolOpt`. Each helper accepts both a primary (camelCase) and
/// a fallback (snake_case) key, prefers the camelCase value when both
/// are present (R19.2), and tolerates numeric strings for numeric
/// fields (R28).
///
/// Money helpers round to 2 decimal places (R28.4).
///
/// Marked `abstract final` so callers can't extend or instantiate it —
/// these are pure static helpers, not state.
abstract final class OrderParser {
  /// Reads a required double from [j], trying [camelKey] first then
  /// the optional [snakeKey].
  ///
  /// Accepts `num` and numeric `String` values. Returns the supplied
  /// [defaultValue] (default `0.0`) when the field is absent or
  /// unparseable; this matches the lenient design the live backend
  /// requires for fields like `rating` that can come back as `0` or
  /// `"0.00"`.
  static double readDouble(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
    double defaultValue = 0.0,
  ]) {
    final Object? v = _pick(j, camelKey, snakeKey);
    if (v is num) return v.toDouble();
    if (v is String) {
      final double? parsed = double.tryParse(v);
      if (parsed != null) return parsed;
    }
    return defaultValue;
  }

  /// Reads an optional double from [j], trying [camelKey] first then
  /// the optional [snakeKey].
  ///
  /// Returns null when the field is absent, null, or unparseable.
  static double? readDoubleOpt(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
  ]) {
    final Object? v = _pick(j, camelKey, snakeKey);
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Reads a required money value from [j], rounded to 2 decimal
  /// places (R28.4).
  ///
  /// Accepts both numbers and numeric strings (the profile route
  /// returns money fields as strings; stats / earnings return them as
  /// numbers).
  static double readMoney(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
  ]) {
    final double raw = readDouble(j, camelKey, snakeKey);
    return _round2(raw);
  }

  /// Reads an optional money value from [j], rounded to 2 decimal
  /// places when present.
  static double? readMoneyOpt(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
  ]) {
    final double? raw = readDoubleOpt(j, camelKey, snakeKey);
    if (raw == null) return null;
    return _round2(raw);
  }

  /// Reads a required int from [j].
  ///
  /// Accepts `int`, `num` (truncates), and numeric `String`. Returns
  /// the supplied [defaultValue] (default `0`) when the field is
  /// absent or unparseable.
  static int readInt(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
    int defaultValue = 0,
  ]) {
    final Object? v = _pick(j, camelKey, snakeKey);
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final int? parsed = int.tryParse(v);
      if (parsed != null) return parsed;
      // Allow numeric strings like "3.0".
      final double? d = double.tryParse(v);
      if (d != null) return d.toInt();
    }
    return defaultValue;
  }

  /// Reads an optional int from [j].
  static int? readIntOpt(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
  ]) {
    final Object? v = _pick(j, camelKey, snakeKey);
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final int? parsed = int.tryParse(v);
      if (parsed != null) return parsed;
      final double? d = double.tryParse(v);
      if (d != null) return d.toInt();
    }
    return null;
  }

  /// Reads a required string from [j].
  ///
  /// Returns the supplied [defaultValue] (default `''`) when absent or
  /// non-string. Non-string scalars are coerced via `toString` so the
  /// parser doesn't blow up on a numeric ID coming back as a number.
  static String readString(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
    String defaultValue = '',
  ]) {
    final Object? v = _pick(j, camelKey, snakeKey);
    if (v == null) return defaultValue;
    if (v is String) return v;
    return v.toString();
  }

  /// Reads an optional string from [j].
  ///
  /// Empty strings are returned as-is (not coerced to null) because
  /// the live backend uses `""` as a meaningful sentinel for "not
  /// configured" on store-info's `phone` field.
  static String? readStringOpt(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
  ]) {
    final Object? v = _pick(j, camelKey, snakeKey);
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  /// Reads a required bool from [j].
  ///
  /// Accepts native booleans, numeric `0` / non-zero, and the strings
  /// `"true"`, `"false"`, `"1"`, `"0"` (case-insensitive). Returns
  /// [defaultValue] for any other shape.
  static bool readBool(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
    bool defaultValue = false,
  ]) {
    return readBoolOpt(j, camelKey, snakeKey) ?? defaultValue;
  }

  /// Reads an optional bool from [j].
  static bool? readBoolOpt(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
  ]) {
    final Object? v = _pick(j, camelKey, snakeKey);
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      switch (v.toLowerCase()) {
        case 'true':
        case '1':
          return true;
        case 'false':
        case '0':
          return false;
      }
    }
    return null;
  }

  /// Reads a list of `Map<String, dynamic>` from [j].
  ///
  /// Returns an empty list when the field is absent or not a list.
  /// Non-map elements inside a present list are filtered out so the
  /// parser tolerates partial backend responses.
  static List<Map<String, dynamic>> readMapList(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
  ]) {
    final Object? v = _pick(j, camelKey, snakeKey);
    if (v is! List) return const <Map<String, dynamic>>[];
    return v
        .whereType<Map<dynamic, dynamic>>()
        .map<Map<String, dynamic>>(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  /// Reads a nested object from [j].
  ///
  /// Returns null when the field is absent or not a map.
  static Map<String, dynamic>? readMap(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
  ]) {
    final Object? v = _pick(j, camelKey, snakeKey);
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Picks the value for [camelKey] when present (and non-null), else
  /// falls back to [snakeKey] when supplied.
  ///
  /// Preferring camelCase implements R19.2 (when both are present, the
  /// camelCase value wins).
  static Object? _pick(
    Map<String, dynamic> j,
    String camelKey, [
    String? snakeKey,
  ]) {
    if (j.containsKey(camelKey)) {
      final Object? v = j[camelKey];
      if (v != null) return v;
    }
    if (snakeKey != null && j.containsKey(snakeKey)) {
      return j[snakeKey];
    }
    // Camel-case key is present but null and no snake fallback — return
    // null so the caller can apply its default.
    return j[camelKey];
  }

  /// Rounds [value] to 2 decimal places, away from zero on the final
  /// digit (banker's-style rounding via `(x * 100).round() / 100`).
  static double _round2(double value) => (value * 100).round() / 100;
}
