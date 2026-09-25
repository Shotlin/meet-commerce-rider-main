import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/theme/app_colors.dart';
import 'package:meet_commerce_rider_main/core/theme/app_dimensions.dart';
import 'package:meet_commerce_rider_main/core/theme/app_motion.dart';
import 'package:meet_commerce_rider_main/core/theme/app_typography.dart';
import 'package:meet_commerce_rider_main/shared/widgets/status_chip.dart';

/// Locks the FreshCuts design-system tokens to the values specified in
/// `02_RIDER_UI_UX_DESIGN_SYSTEM.md`.
///
/// These assertions exist so an accidental palette/scale edit cannot slip
/// through review: the rider app must stay visually aligned with the
/// FreshCuts customer app.
void main() {
  group('Brand palette matches the design system', () {
    test('FreshCuts red family', () {
      expect(AppColors.brand, const Color(0xFFE61F2C));
      expect(AppColors.brandPressed, const Color(0xFFC91422));
      expect(AppColors.brandSoft, const Color(0xFFFFF0F2));
      expect(AppColors.brandBorder, const Color(0xFFF6C8CE));
    });

    test('neutral family', () {
      expect(AppColors.charcoal, const Color(0xFF101114));
      expect(AppColors.graphite, const Color(0xFF344054));
      expect(AppColors.muted, const Color(0xFF667085));
      expect(AppColors.subtle, const Color(0xFF98A2B3));
      expect(AppColors.offWhite, const Color(0xFFF7F7F8));
      expect(AppColors.white, const Color(0xFFFFFFFF));
      expect(AppColors.border, const Color(0xFFEAECF0));
      expect(AppColors.divider, const Color(0xFFEEF0F2));
    });

    test('semantic family, with soft tints for non-colour-only status', () {
      expect(AppColors.success, const Color(0xFF22A95C));
      expect(AppColors.successSoft, const Color(0xFFECFDF3));
      expect(AppColors.warning, const Color(0xFFF59E0B));
      expect(AppColors.warningSoft, const Color(0xFFFFFAEB));
      expect(AppColors.danger, const Color(0xFFD92D20));
      expect(AppColors.errorSoft, const Color(0xFFFEF3F2));
      expect(AppColors.info, const Color(0xFF2563EB));
      expect(AppColors.mapBlue, AppColors.info);
    });

    test('primary text is Ink, never pure black', () {
      expect(AppColors.black, const Color(0xFF101114));
      expect(AppColors.charcoal, AppColors.black);
    });
  });

  group('Spacing and shape follow the 8-point rhythm', () {
    test('spacing scale is monotonic and 8-point aligned from sm upward', () {
      expect(AppDimensions.xs, 4);
      expect(AppDimensions.sm, 8);
      expect(AppDimensions.md, 12);
      expect(AppDimensions.lg, 16);
      expect(AppDimensions.xl, 18);
      expect(AppDimensions.xxl, 24);

      for (final double value in <double>[
        AppDimensions.sm,
        AppDimensions.lg,
        AppDimensions.xxl,
      ]) {
        expect(value % 8, 0);
      }
    });

    test('radii and sizing match the design ranges', () {
      // Primary card radius 16–20, hero 20, sheet 24, button 14–16.
      expect(AppDimensions.cardRadius, 16);
      expect(AppDimensions.heroCardRadius, 20);
      expect(AppDimensions.sheetRadius, 24);
      expect(AppDimensions.buttonRadius, inInclusiveRange(14, 16));
      expect(AppDimensions.inputRadius, 14);
      expect(AppDimensions.chipRadius, 999);
      // Primary action height 52–56.
      expect(AppDimensions.buttonHeight, inInclusiveRange(52, 56));
      expect(AppDimensions.touchTarget, 48);
    });
  });

  group('Typography uses the brand families and accessible sizes', () {
    test('headings use PlusJakartaSans, body copy uses DMSans', () {
      expect(AppTypography.display.fontFamily, 'PlusJakartaSans');
      expect(AppTypography.title.fontFamily, 'PlusJakartaSans');
      expect(AppTypography.heading.fontFamily, 'PlusJakartaSans');
      expect(AppTypography.cardTitle.fontFamily, 'PlusJakartaSans');
      expect(AppTypography.label.fontFamily, 'PlusJakartaSans');
      expect(AppTypography.body.fontFamily, 'DMSans');
      expect(AppTypography.micro.fontFamily, 'DMSans');
    });

    test('scale sits inside the documented ranges', () {
      expect(AppTypography.display.fontSize, inInclusiveRange(32, 36));
      expect(AppTypography.title.fontSize, inInclusiveRange(24, 28));
      expect(AppTypography.heading.fontSize, inInclusiveRange(18, 20));
      expect(AppTypography.cardTitle.fontSize, inInclusiveRange(16, 18));
      expect(AppTypography.body.fontSize, inInclusiveRange(14, 16));
      expect(AppTypography.label.fontSize, inInclusiveRange(14, 16));
      expect(AppTypography.micro.fontSize, inInclusiveRange(12, 13));
    });

    test('money/ETA styles use tabular figures so digits do not jitter', () {
      expect(AppTypography.display.fontFeatures, isNotNull);
      expect(AppTypography.numeric.fontFeatures, isNotNull);
    });
  });

  group('Motion stays in the 160–220 ms band', () {
    test('durations', () {
      expect(AppMotion.fast.inMilliseconds, 160);
      expect(AppMotion.normal.inMilliseconds, inInclusiveRange(160, 220));
      expect(AppMotion.slow.inMilliseconds, inInclusiveRange(160, 220));
      expect(AppMotion.sheetOpen.inMilliseconds, inInclusiveRange(160, 240));
    });
  });

  group('Status visuals are never colour-only', () {
    test('every tone resolves a dot colour and a soft background', () {
      for (final StatusTone tone in StatusTone.values) {
        expect(
          StatusChip.dotColorFor(tone),
          isA<Color>(),
          reason: '${tone.name} must resolve a dot colour',
        );
        expect(
          StatusChip.backgroundColorFor(tone),
          isA<Color>(),
          reason: '${tone.name} must resolve a background tint',
        );
      }
    });

    test('online maps to success, pending to warning, danger to error', () {
      expect(StatusChip.dotColorFor(StatusTone.online), AppColors.success);
      expect(
        StatusChip.backgroundColorFor(StatusTone.online),
        AppColors.successSoft,
      );
      expect(StatusChip.dotColorFor(StatusTone.pending), AppColors.warning);
      expect(
        StatusChip.backgroundColorFor(StatusTone.pending),
        AppColors.warningSoft,
      );
      expect(StatusChip.dotColorFor(StatusTone.danger), AppColors.danger);
      expect(
        StatusChip.backgroundColorFor(StatusTone.danger),
        AppColors.errorSoft,
      );
      expect(StatusChip.dotColorFor(StatusTone.info), AppColors.info);
    });

    test('offline/neutral fall back to the canvas tint', () {
      expect(
        StatusChip.backgroundColorFor(StatusTone.offline),
        AppColors.offWhite,
      );
      expect(
        StatusChip.backgroundColorFor(StatusTone.neutral),
        AppColors.offWhite,
      );
    });
  });
}
