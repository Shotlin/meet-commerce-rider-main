import 'package:flutter/material.dart';

/// FreshCuts brand palette for the Freashcut Rider app.
///
/// Source of truth: `02_RIDER_UI_UX_DESIGN_SYSTEM.md` §2. The rider app
/// shares the customer app's red/white/ink family so the two read as one
/// product, with green reserved strictly for semantic success (online,
/// delivered) — never as a second brand colour.
///
/// Token rules:
/// - brand action colour is FreshCuts red;
/// - primary text is Ink, never pure black;
/// - surfaces are white cards on a soft grey canvas;
/// - soft tints exist for the semantic states so status never relies on a
///   saturated colour alone.
///
/// Marked `abstract final` so the class can never be instantiated or
/// extended; callers reach the values via `AppColors.<token>`.
abstract final class AppColors {
  // ────────────────────────────────────────────────────────────────────────
  // Primary — FreshCuts red
  // ────────────────────────────────────────────────────────────────────────

  /// FreshCuts red — the single brand action colour (primary buttons,
  /// active states, offer surfaces, brand accents).
  static const Color brand = Color(0xFFE61F2C);

  /// Pressed/active shade of [brand].
  static const Color brandPressed = Color(0xFFC91422);

  /// Tinted brand surface (offer cards, active-delivery accents).
  static const Color brandSoft = Color(0xFFFFF0F2);

  /// Border for brand-tinted surfaces.
  static const Color brandBorder = Color(0xFFF6C8CE);

  // ────────────────────────────────────────────────────────────────────────
  // Neutral — ink, text, canvas, surfaces
  // ────────────────────────────────────────────────────────────────────────

  /// Ink / primary text. Also used for dark hero surfaces that need to read
  /// as "very dark neutral", not pure black.
  static const Color black = Color(0xFF101114);

  /// Ink for primary text on white surfaces and AppBar foregrounds.
  ///
  /// Same value as [black] by design: the FreshCuts system defines one
  /// primary text colour. The alias stays so call sites keep reading in
  /// terms of their role (text vs. surface).
  static const Color charcoal = Color(0xFF101114);

  /// Secondary text (supporting copy, addresses, order meta).
  static const Color graphite = Color(0xFF344054);

  /// Muted text (helper copy, disabled states, captions).
  static const Color muted = Color(0xFF667085);

  /// Subtle text (lowest-emphasis metadata; never for critical delivery
  /// steps).
  static const Color subtle = Color(0xFF98A2B3);

  /// App canvas — the soft grey background behind white cards.
  static const Color offWhite = Color(0xFFF7F7F8);

  /// Pure white surface (cards, sheets, AppBars).
  static const Color white = Color(0xFFFFFFFF);

  /// Hairline border for cards, list separators and secondary outlines.
  static const Color border = Color(0xFFEAECF0);

  /// Intra-card divider (lighter than [border]).
  static const Color divider = Color(0xFFEEF0F2);

  // ────────────────────────────────────────────────────────────────────────
  // Semantic — success, warning, error, info
  // ────────────────────────────────────────────────────────────────────────

  /// Semantic success — Online, Completed, Delivered.
  static const Color success = Color(0xFF22A95C);

  /// Tinted success surface.
  static const Color successSoft = Color(0xFFECFDF3);

  /// Semantic warning — Pending, COD Due, Reconnecting.
  static const Color warning = Color(0xFFF59E0B);

  /// Tinted warning surface.
  static const Color warningSoft = Color(0xFFFFFAEB);

  /// Semantic error — Destructive, Failed, Cancelled.
  static const Color danger = Color(0xFFD92D20);

  /// Tinted error surface.
  static const Color errorSoft = Color(0xFFFEF3F2);

  /// Info accent — route / navigation secondary colour.
  static const Color info = Color(0xFF2563EB);

  /// Legacy alias for [info]; the map polyline / external-navigation accent.
  static const Color mapBlue = info;
}
