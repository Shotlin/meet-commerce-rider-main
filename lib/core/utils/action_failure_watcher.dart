/// Tracks consecutive failures for critical actions (R27.5).
///
/// When the same action key fails twice within [_window], the
/// diagnostic expander should be surfaced to the rider.
class ActionFailureWatcher {
  /// Window within which two failures trigger the diagnostic.
  static const Duration _window = Duration(seconds: 10);

  final Map<String, _FailureRecord> _records = <String, _FailureRecord>{};

  /// Records a failure for [key] with the given [message] and optional
  /// [details] map entries.
  void record(
    String key,
    String message, {
    Map<String, String> details = const <String, String>{},
  }) {
    final DateTime now = DateTime.now();
    final _FailureRecord? prev = _records[key];
    _records[key] = _FailureRecord(
      message: message,
      details: details,
      timestamp: now,
      previousTimestamp: prev?.timestamp,
      previousMessage: prev?.message,
    );
  }

  /// Returns `true` when [key] has failed twice within [_window].
  bool shouldShowDiagnostic(String key) {
    final _FailureRecord? r = _records[key];
    if (r == null || r.previousTimestamp == null) return false;
    return r.timestamp.difference(r.previousTimestamp!) <= _window;
  }

  /// Returns the diagnostic rows for [key], suitable for
  /// `DiagnosticExpander.rows`.
  List<MapEntry<String, String>> diagnosticRows(String key) {
    final _FailureRecord? r = _records[key];
    if (r == null) return const <MapEntry<String, String>>[];
    return <MapEntry<String, String>>[
      MapEntry<String, String>('Error', r.message),
      ...r.details.entries,
      if (r.previousMessage != null)
        MapEntry<String, String>('Previous', r.previousMessage!),
      MapEntry<String, String>(
        'At',
        r.timestamp.toIso8601String().substring(11, 19),
      ),
      if (r.previousTimestamp != null)
        MapEntry<String, String>(
          'Previous at',
          r.previousTimestamp!.toIso8601String().substring(11, 19),
        ),
    ];
  }

  /// Clears the failure history for [key].
  void clear(String key) => _records.remove(key);

  /// Alias for [clear] used by delivery sheets.
  void reset(String key) => clear(key);
}

class _FailureRecord {
  _FailureRecord({
    required this.message,
    required this.details,
    required this.timestamp,
    this.previousTimestamp,
    this.previousMessage,
  });

  final String message;
  final Map<String, String> details;
  final DateTime timestamp;
  final DateTime? previousTimestamp;
  final String? previousMessage;
}
