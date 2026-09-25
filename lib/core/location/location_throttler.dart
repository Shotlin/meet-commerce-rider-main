/// Backwards-compat alias for [SlidingWindowThrottler].
///
/// The throttler implementation moved to `sliding_window_throttler.dart`
/// after Task 8.2. This re-export keeps existing import sites compiling
/// while we migrate them in a follow-up pass.
export 'sliding_window_throttler.dart';
