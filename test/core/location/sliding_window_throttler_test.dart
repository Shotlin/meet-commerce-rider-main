import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/location/sliding_window_throttler.dart';

/// Standard unit tests for [SlidingWindowThrottler]. The Property 3
/// guarantees over arbitrary event traces are covered separately by
/// [`sliding_window_throttler_property_test.dart`].
void main() {
  const Duration window = Duration(seconds: 60);

  DateTime t(int seconds) =>
      DateTime.utc(2026, 1, 1).add(Duration(seconds: seconds));

  group('canEmit / accept', () {
    test('with budget=2, 3rd emit in the same 60s window is rejected', () {
      final SlidingWindowThrottler throttler = SlidingWindowThrottler(
        window: window,
        initialBudget: 2,
      );

      expect(throttler.canEmit(t(0)), isTrue);
      throttler.accept(t(0));
      expect(throttler.canEmit(t(10)), isTrue);
      throttler.accept(t(10));
      expect(throttler.canEmit(t(20)), isFalse);
      expect(throttler.currentCount, 2);
    });

    test('after 60s, the first sample evicts and a new one is accepted', () {
      final SlidingWindowThrottler throttler = SlidingWindowThrottler(
        window: window,
        initialBudget: 2,
      );

      throttler.accept(t(0));
      throttler.accept(t(10));
      // After 61s the t(0) timestamp falls outside the window.
      expect(throttler.canEmit(t(61)), isTrue);
      throttler.accept(t(61));
      expect(throttler.currentCount, 2); // t(10) and t(61)
    });

    test('exactly 60s after a stamp counts as inside the window', () {
      final SlidingWindowThrottler throttler = SlidingWindowThrottler(
        window: window,
        initialBudget: 1,
      );
      throttler.accept(t(0));
      // At t=60 the window is [t(0), t(60)] inclusive of right endpoint;
      // we evict only stamps strictly before the cutoff (t-60), so t(0)
      // is at the cutoff and remains in the window.
      expect(throttler.canEmit(t(60)), isFalse);
      // At t=60.001 (slightly after) the stamp ages out.
      expect(throttler.canEmit(t(61)), isTrue);
    });
  });

  group('setBudget', () {
    test('lowering the budget below currentCount disables further emits', () {
      final SlidingWindowThrottler throttler = SlidingWindowThrottler(
        window: window,
        initialBudget: 12,
      );

      for (int s = 0; s < 6; s++) {
        throttler.accept(t(s));
      }
      expect(throttler.currentCount, 6);
      throttler.setBudget(2);
      expect(throttler.canEmit(t(7)), isFalse);
      // Stamps must age out before emits resume.
      expect(throttler.canEmit(t(70)), isTrue);
    });

    test('raising the budget allows more emits in the same window', () {
      final SlidingWindowThrottler throttler = SlidingWindowThrottler(
        window: window,
        initialBudget: 2,
      );
      throttler.accept(t(0));
      throttler.accept(t(1));
      expect(throttler.canEmit(t(2)), isFalse);
      throttler.setBudget(6);
      expect(throttler.canEmit(t(2)), isTrue);
    });

    test('does not clear the existing timestamp history', () {
      final SlidingWindowThrottler throttler = SlidingWindowThrottler(
        window: window,
        initialBudget: 12,
      );
      throttler.accept(t(0));
      throttler.accept(t(1));
      throttler.setBudget(6);
      expect(throttler.currentCount, 2);
    });
  });

  group('reset', () {
    test('clears the timestamp history', () {
      final SlidingWindowThrottler throttler = SlidingWindowThrottler(
        window: window,
        initialBudget: 2,
      );
      throttler.accept(t(0));
      throttler.accept(t(1));
      throttler.reset();
      expect(throttler.currentCount, 0);
      expect(throttler.canEmit(t(2)), isTrue);
    });
  });
}
