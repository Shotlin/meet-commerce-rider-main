import 'package:glados/glados.dart';

import 'package:meet_commerce_rider_main/core/location/sliding_window_throttler.dart';

/// Feature: freashcut-rider, Property 3:
/// For any sliding 60-second window, count(uploads) <= Rate_Budget(state).
///
/// We model an arbitrary event trace as a list of `(deltaMs, budget)`
/// pairs where each pair represents a candidate emit. The simulator:
/// 1. Advances simulated time by `deltaMs`.
/// 2. Sets the throttler's budget (so the simulator captures
///    profile-tightening + profile-relaxing transitions).
/// 3. Asks the throttler whether the emit is permitted at the new time.
/// 4. If yes, accepts the emit.
///
/// At every accepted timestamp we then assert that the count of accepted
/// timestamps within the last 60s does not exceed the *maximum* budget
/// observed during the window. The strongest practical statement of the
/// design's invariant: over any sub-window where the budget is constant,
/// the count is bounded by that constant; over the whole window, by the
/// maximum constant held during the window.
///
/// Validates: Requirements R17.4.
void main() {
  /// Each event is a pair: time delta in [0,30000] ms, budget in [0,12].
  /// Generators are independent because Glados2 takes two univariate
  /// generators and zips them inside the test body.
  final Generator<List<int>> deltaList = any.listWithLengthInRange(
    1,
    50,
    any.intInRange(0, 30000),
  );
  final Generator<List<int>> budgetList = any.listWithLengthInRange(
    1,
    50,
    any.intInRange(0, 12),
  );

  Glados2<List<int>, List<int>>(
    deltaList,
    budgetList,
    ExploreConfig(numRuns: 25),
  ).test('rate budget is never exceeded over any 60s sliding window', (
    List<int> deltas,
    List<int> budgets,
  ) {
    final int len = deltas.length < budgets.length
        ? deltas.length
        : budgets.length;
    if (len == 0) return;

    final SlidingWindowThrottler throttler = SlidingWindowThrottler(
      window: const Duration(seconds: 60),
      initialBudget: budgets[0],
    );

    DateTime now = DateTime.utc(2026, 1, 1);
    final List<DateTime> accepted = <DateTime>[];
    // Keep the budget history with timestamps so we can find the max
    // budget held during the window.
    final List<({DateTime at, int budget})> budgetHistory =
        <({DateTime at, int budget})>[(at: now, budget: budgets[0])];

    for (int i = 0; i < len; i++) {
      now = now.add(Duration(milliseconds: deltas[i]));
      final int newBudget = budgets[i];
      if (newBudget != throttler.budget) {
        throttler.setBudget(newBudget);
        budgetHistory.add((at: now, budget: newBudget));
      }
      if (throttler.canEmit(now)) {
        throttler.accept(now);
        accepted.add(now);

        // Property check: count of accepted timestamps in
        // [now - 60s, now] must not exceed the max budget held during
        // that window.
        final DateTime cutoff = now.subtract(const Duration(seconds: 60));
        final int countInWindow = accepted
            .where((DateTime ts) => ts.isAfter(cutoff))
            .length;

        final int maxBudgetInWindow = budgetHistory
            .where((({DateTime at, int budget}) e) => !e.at.isBefore(cutoff))
            .map((({DateTime at, int budget}) e) => e.budget)
            .fold<int>(
              // Fold seed = the budget that was in force at the cutoff.
              _budgetAt(budgetHistory, cutoff),
              (int acc, int b) => b > acc ? b : acc,
            );

        if (countInWindow > maxBudgetInWindow) {
          fail(
            'rate budget violated at i=$i: $countInWindow accepts '
            'in last 60s, max budget held = $maxBudgetInWindow',
          );
        }
      }
    }
  });
}

/// Returns the budget that was in force at [t] given the history of
/// `setBudget` calls (most recent at the end).
int _budgetAt(List<({DateTime at, int budget})> history, DateTime t) {
  int current = history.first.budget;
  for (final ({DateTime at, int budget}) entry in history) {
    if (entry.at.isAfter(t)) break;
    current = entry.budget;
  }
  return current;
}
