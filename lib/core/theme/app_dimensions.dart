/// Spacing, shape and size tokens for the Freashcut Rider app.
///
/// Source of truth: `02_RIDER_UI_UX_DESIGN_SYSTEM.md` §4 (8-point rhythm)
/// and §5 (button sizing). Screens and shared widgets must read these
/// values instead of inventing new ones so the app stays visually
/// consistent as screens are rebuilt.
///
/// Marked `abstract final` so the class can never be instantiated or
/// extended; callers reach the values via `AppDimensions.<token>`.
abstract final class AppDimensions {
  // ────────────────────────────────────────────────────────────────────────
  // Spacing (8-point rhythm)
  // ────────────────────────────────────────────────────────────────────────

  /// Tightest gap (icon-to-label).
  static const double xs = 4;

  /// Standard internal gap.
  static const double sm = 8;

  /// Comfortable internal gap.
  static const double md = 12;

  /// Standard screen gutter / card padding.
  static const double lg = 16;

  /// Hero card inner padding.
  static const double xl = 18;

  /// Section-to-section gap.
  static const double xxl = 24;

  /// Horizontal screen padding.
  static const double screenPadding = lg;

  /// Padding for dense info cards.
  static const double denseCardPadding = lg;

  /// Padding for hero/decision cards (availability, offer, completion).
  static const double heroCardPadding = xl;

  /// Gap between major sections.
  static const double sectionGap = xxl;

  /// Gap between rows inside a card.
  static const double rowGap = md;

  // ────────────────────────────────────────────────────────────────────────
  // Shape
  // ────────────────────────────────────────────────────────────────────────

  /// Default radius for cards and surfaces.
  static const double cardRadius = 16;

  /// Radius for large hero cards.
  static const double heroCardRadius = 20;

  /// Top radius for bottom sheets.
  static const double sheetRadius = 24;

  /// Radius for buttons.
  static const double buttonRadius = 16;

  /// Radius for text fields and small inputs.
  static const double inputRadius = 14;

  /// Pill radius for status chips.
  static const double chipRadius = 999;

  // ────────────────────────────────────────────────────────────────────────
  // Sizing
  // ────────────────────────────────────────────────────────────────────────

  /// Height for full-width primary/secondary workflow actions
  /// (design §5: 52–56 px).
  static const double buttonHeight = 54;

  /// Floor for any interactive target (accessibility §25).
  static const double touchTarget = 48;

  /// Standard hairline width.
  static const double hairline = 1;

  // ────────────────────────────────────────────────────────────────────────
  // Brand mark
  // ────────────────────────────────────────────────────────────────────────

  /// FreshCuts mark size on splash / hero positions.
  static const double brandMarkLarge = 72;

  /// FreshCuts mark size in screen headers (login, onboarding).
  static const double brandMarkSmall = 40;
}
