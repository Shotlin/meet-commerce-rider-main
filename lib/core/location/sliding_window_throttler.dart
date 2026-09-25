import 'dart:collection';

/// Pure-Dart sliding-window rate limiter used by the rider app's
/// [LocationUploader] (Task 8.4).
///
/// Property 3 (R17.4): for any sliding 60-second window, the number of
/// accepted samples must not exceed the rate budget for the profile in
/// force at the end of that window. `SlidingWindowThrottler` is the
/// executable form of that property — it is a plain data structure
/// with no timers or streams; the caller decides "now".
///
/// Usage:
///
/// ```dart
/// final throttler = SlidingWindowThrottler(
///   window: AppConstants.locationRateWindow,
///   initialBudget: AppConstants.locationBudgetWaitingPerMinute,
/// );
/// if (throttler.canEmit(now)) {
///   await uploader.send(sample);
///   throttler.accept(now);
/// }
/// ```
///
/// The state-change semantics are deliberate: when the profile
/// tightens (e.g., from `waitingOnline` to `inTransitToCustomer`), the
/// budget grows; when it relaxes, the budget shrinks. We do NOT clear
/// existing stamps on [setBudget] because the property is over the past
/// 60 seconds regardless of when the budget changed.
class SlidingWindowThrottler {
  /// Constructs a throttler with the given rolling [window] and
  /// initial [initialBudget] (samples per [window]).
  SlidingWindowThrottler({required this.window, required int initialBudget})
    : _budget = initialBudget,
      assert(initialBudget >= 0, 'initialBudget must be >= 0');

  /// Rolling window over which the budget is enforced.
  final Duration window;

  int _budget;
  final Queue<DateTime> _stamps = Queue<DateTime>();

  /// Current budget (samples per [window]).
  int get budget => _budget;

  /// Number of timestamps in the active window. Recomputed on demand by
  /// evicting expired stamps relative to the most recent timestamp;
  /// the caller-driven nature of `canEmit`/`accept` keeps this honest.
  int get currentCount => _stamps.length;

  /// Returns `true` iff a sample taken at [now] is permitted under the
  /// current budget. Does NOT record the sample — call [accept] after
  /// the upload actually succeeds (or at least is dispatched).
  bool canEmit(DateTime now) {
    _evict(now);
    return _stamps.length < _budget;
  }

  /// Records that a sample was emitted at [now]. Pre-condition: the
  /// caller has just observed `canEmit(now) == true`. We do not enforce
  /// the precondition here so callers can record forced emits (e.g. the
  /// REST keepalive after foreground resume) that legitimately ignore
  /// `canEmit`.
  void accept(DateTime now) {
    _evict(now);
    _stamps.addLast(now);
  }

  /// Adjusts the active budget without clearing the timestamp history.
  ///
  /// The history is intentionally preserved so transitions such as
  /// `inTransitToCustomer` (12/min) -> `waitingOnline` (2/min) tighten
  /// the rate immediately even on the next emit attempt.
  void setBudget(int newBudget) {
    assert(newBudget >= 0, 'budget must be >= 0');
    _budget = newBudget;
  }

  /// Clears the timestamp history. Used on offline transitions (R17.5)
  /// where we want subsequent emits to start fresh.
  void reset() {
    _stamps.clear();
  }

  void _evict(DateTime now) {
    final DateTime cutoff = now.subtract(window);
    // Strict inequality: a stamp exactly at the cutoff (e.g. t=0 with
    // now=t+window) is still considered inside the window per
    // Property 3's "any sliding 60s window" semantics. Only stamps
    // strictly before the cutoff age out.
    while (_stamps.isNotEmpty && _stamps.first.isBefore(cutoff)) {
      _stamps.removeFirst();
    }
  }
}
