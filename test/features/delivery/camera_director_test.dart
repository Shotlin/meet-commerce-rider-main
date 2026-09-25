import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/features/delivery/presentation/camera_director.dart';

/// Unit tests for [CameraDirector]'s suppression-window behaviour
/// (R12.6) and phase-fit tracking (R12.7).
///
/// `maybeFitBounds` and `recenter` touch a [GoogleMapController]
/// which is impossible to instantiate in pure Dart; the pure-Dart
/// logic the screen relies on (pan timestamp + `shouldAutoFit` +
/// phase-fit flag + `resetPhaseFit`) is exercised here directly with
/// a fixed `now`.
void main() {
  group('CameraDirector', () {
    test('shouldAutoFit returns true before any pan has been recorded', () {
      final CameraDirector director = CameraDirector();
      expect(director.shouldAutoFit(DateTime(2024, 1, 1, 12)), isTrue);
      expect(director.lastUserPanAt, isNull);
      expect(director.hasFittedForPhase, isFalse);
    });

    test('onUserPan records the latest pan timestamp', () {
      final CameraDirector director = CameraDirector();
      director.onUserPan();
      expect(director.lastUserPanAt, isNotNull);
    });

    test('onUserPan suppresses auto-fit for 6 s; the next call after '
        'the window has elapsed is allowed (R12.6)', () {
      final CameraDirector director = CameraDirector();
      final DateTime t0 = DateTime(2024, 1, 1, 12, 0, 0);
      director.onUserPanAt(t0);

      // Inside the 6 s window: no auto-fit.
      expect(director.shouldAutoFit(t0), isFalse);
      expect(
        director.shouldAutoFit(t0.add(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        director.shouldAutoFit(t0.add(const Duration(seconds: 5))),
        isFalse,
      );

      // At the window boundary: re-enabled.
      expect(
        director.shouldAutoFit(t0.add(const Duration(seconds: 6))),
        isTrue,
      );

      // Beyond the window: still allowed.
      expect(
        director.shouldAutoFit(t0.add(const Duration(seconds: 30))),
        isTrue,
      );
    });

    test('a second pan restarts the suppression window from the new '
        'timestamp (latest-pan semantics, not a sticky flag)', () {
      final CameraDirector director = CameraDirector();
      final DateTime t0 = DateTime(2024, 1, 1, 12, 0, 0);
      director.onUserPanAt(t0);
      expect(
        director.shouldAutoFit(t0.add(const Duration(seconds: 5))),
        isFalse,
      );

      director.onUserPanAt(t0.add(const Duration(seconds: 5)));

      // 5 s after the second pan: still suppressed.
      expect(
        director.shouldAutoFit(t0.add(const Duration(seconds: 10))),
        isFalse,
      );
      // 6 s after the second pan: re-enabled.
      expect(
        director.shouldAutoFit(t0.add(const Duration(seconds: 11))),
        isTrue,
      );
    });

    test('custom suppression window is honoured', () {
      final CameraDirector director = CameraDirector(
        suppressionWindow: const Duration(seconds: 2),
      );
      final DateTime t0 = DateTime(2024, 1, 1, 12, 0, 0);
      director.onUserPanAt(t0);

      expect(
        director.shouldAutoFit(t0.add(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        director.shouldAutoFit(t0.add(const Duration(seconds: 2))),
        isTrue,
      );
    });

    test('resetPhaseFit clears both the phase-fit flag and the manual '
        'pan timestamp so the next auto-fit is allowed immediately', () {
      final CameraDirector director = CameraDirector();
      final DateTime t0 = DateTime(2024, 1, 1, 12, 0, 0);
      director.onUserPanAt(t0);
      expect(director.shouldAutoFit(t0), isFalse);

      director.resetPhaseFit();

      expect(director.lastUserPanAt, isNull);
      expect(director.hasFittedForPhase, isFalse);
      // Now eligible regardless of where t0 sat in the window.
      expect(director.shouldAutoFit(t0), isTrue);
    });
  });
}
