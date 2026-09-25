import 'package:flutter/animation.dart';

/// Motion tokens for the Freashcut Rider app.
///
/// Source of truth: `02_RIDER_UI_UX_DESIGN_SYSTEM.md` §24 — transitions
/// explain state changes, they do not entertain. Durations live in the
/// 160–220 ms band so the app feels operationally fast on real devices
/// while still registering as a change of state.
///
/// Marked `abstract final` so the class can never be instantiated or
/// extended; callers reach values via `AppMotion.<token>`.
abstract final class AppMotion {
  /// Snappy micro-transitions (status chip changes, switch toggles).
  static const Duration fast = Duration(milliseconds: 160);

  /// Default screen, tab and in-card transitions.
  static const Duration normal = Duration(milliseconds: 200);

  /// Camera fits, sheet snaps and larger layout changes.
  static const Duration slow = Duration(milliseconds: 220);

  /// Bottom-sheet open animation — a subtle spring, never a bounce.
  static const Duration sheetOpen = Duration(milliseconds: 240);

  /// Standard easing curve. `easeOutCubic` decelerates into rest, which
  /// reads as "premium and finished" for sheet snaps and camera fits.
  static const Curve easing = Curves.easeOutCubic;

  /// Curve for bottom-sheet presentation (slightly firmer than [easing]
  /// so the sheet lands instead of drifting).
  static const Curve sheetEasing = Curves.easeOutQuart;
}
