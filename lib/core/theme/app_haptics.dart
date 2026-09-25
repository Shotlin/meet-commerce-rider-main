import 'package:flutter/services.dart';

/// Haptic feedback tokens for the Freashcut Rider app.
///
/// Source of truth: `02_RIDER_UI_UX_DESIGN_SYSTEM.md` §24 — motion and
/// haptics explain state changes, they do not entertain:
///
/// - [accept] — the moment a rider wins an order offer;
/// - [success] — a confirmed delivery (stronger, celebratory but short);
/// - [warning] — failed acceptance, invalid OTP, rejected action;
/// - [light] — small confirmations (toggle, chip change).
///
/// Deliberately a thin wrapper so the call sites read as product intent
/// rather than platform API calls, and so a future platform-specific tuning
/// pass happens in exactly one file.
abstract final class AppHaptics {
  /// Small confirmation (toggles, chip changes).
  static void light() {
    HapticFeedback.selectionClick();
  }

  /// Standard confirmation haptic (successful accept, saved setting).
  static void accept() {
    HapticFeedback.mediumImpact();
  }

  /// Strong success haptic (delivery confirmed, collection confirmed).
  static void success() {
    HapticFeedback.heavyImpact();
  }

  /// Warning haptic (failed accept, invalid OTP, blocked action).
  static void warning() {
    HapticFeedback.vibrate();
  }
}
