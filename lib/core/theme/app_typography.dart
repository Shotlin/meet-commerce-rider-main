import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography scale for the Freashcut Rider app.
///
/// Source of truth: `02_RIDER_UI_UX_DESIGN_SYSTEM.md` §3.
///
/// Two families, shared with the FreshCuts customer app:
/// - **PlusJakartaSans** — display amounts, screen titles, section/card
///   titles and every button/label (energetic, quick-commerce feel);
/// - **DMSans** — body copy, helper and meta text (warm, legible at 12–15 px
///   where most delivery information lives).
///
/// Conventions enforced here:
/// - sentence case copy; no all-caps beyond very small metadata labels;
/// - money, ETA and distance styles carry tabular figures so digits do not
///   jitter while a value updates;
/// - every style defaults to [AppColors.black] foreground, overridable per
///   call site.
///
/// Marked `abstract final` so the class can never be instantiated or
/// extended; callers reach styles via `AppTypography.<token>`.
abstract final class AppTypography {
  /// Brand heading family.
  static const String headingFamily = 'PlusJakartaSans';

  /// Brand body family.
  static const String bodyFamily = 'DMSans';

  /// Display amount: 34 / 38, w700. Hero money figures, splash and
  /// onboarding headings.
  static const TextStyle display = TextStyle(
    fontFamily: headingFamily,
    fontSize: 34,
    height: 38 / 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.black,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Screen title: 26 / 32, w700. Top-of-screen titles and large leads.
  static const TextStyle title = TextStyle(
    fontFamily: headingFamily,
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.black,
  );

  /// Section title: 19 / 26, w700. Section headers inside a screen.
  static const TextStyle heading = TextStyle(
    fontFamily: headingFamily,
    fontSize: 19,
    height: 26 / 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.black,
  );

  /// Card title: 17 / 24, w600. Titles inside cards, sheets and rows.
  static const TextStyle cardTitle = TextStyle(
    fontFamily: headingFamily,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
    color: AppColors.black,
  );

  /// Body: 15 / 22, w500. Primary running text, form inputs, addresses.
  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w500,
    color: AppColors.black,
  );

  /// Label / button: 15 / 20, w600. Buttons, form labels, chips.
  static const TextStyle label = TextStyle(
    fontFamily: headingFamily,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
    color: AppColors.black,
  );

  /// Helper / meta: 12 / 16, w500. Badges, captions, metadata rows.
  static const TextStyle micro = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
  );

  /// Numeric accent: 15 / 20, w700 with tabular figures.
  ///
  /// Use for inline money, distance and ETA values that update in place.
  static const TextStyle numeric = TextStyle(
    fontFamily: headingFamily,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w700,
    color: AppColors.black,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
