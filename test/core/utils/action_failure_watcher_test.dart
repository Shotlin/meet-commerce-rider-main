import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/utils/action_failure_watcher.dart';

void main() {
  group('ActionFailureWatcher', () {
    test('single failure does not trigger diagnostic', () {
      final ActionFailureWatcher w = ActionFailureWatcher();
      w.record('accept', 'Network error');
      expect(w.shouldShowDiagnostic('accept'), isFalse);
    });

    test('two failures same key within 10s triggers diagnostic', () {
      final ActionFailureWatcher w = ActionFailureWatcher();
      w.record('accept', 'Error 1');
      w.record('accept', 'Error 2');
      expect(w.shouldShowDiagnostic('accept'), isTrue);
      expect(w.diagnosticRows('accept'), isNotEmpty);
    });

    test('different keys do not interfere', () {
      final ActionFailureWatcher w = ActionFailureWatcher();
      w.record('accept', 'Error 1');
      w.record('pickup', 'Error 2');
      expect(w.shouldShowDiagnostic('accept'), isFalse);
      expect(w.shouldShowDiagnostic('pickup'), isFalse);
    });

    test('clear removes the history for a key', () {
      final ActionFailureWatcher w = ActionFailureWatcher();
      w.record('accept', 'Error 1');
      w.record('accept', 'Error 2');
      expect(w.shouldShowDiagnostic('accept'), isTrue);
      w.clear('accept');
      expect(w.shouldShowDiagnostic('accept'), isFalse);
    });

    test('diagnosticRows includes error messages and timestamps', () {
      final ActionFailureWatcher w = ActionFailureWatcher();
      w.record(
        'deliver',
        'OTP invalid',
        details: <String, String>{
          'orderId': 'order-1',
          'path': 'PATCH /deliver',
        },
      );
      w.record('deliver', 'OTP expired');
      final List<MapEntry<String, String>> rows = w.diagnosticRows('deliver');
      expect(
        rows.any((MapEntry<String, String> e) => e.key == 'Error'),
        isTrue,
      );
      expect(rows.any((MapEntry<String, String> e) => e.key == 'At'), isTrue);
      expect(
        rows.any((MapEntry<String, String> e) => e.key == 'Previous'),
        isTrue,
      );
    });
  });
}
