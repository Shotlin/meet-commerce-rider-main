import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';

/// Tone classification for [StatusChip].
///
/// The tone selects the leading-dot color while keeping the pill body
/// neutral. Mapped per `design.md`:
/// online -> success, offline -> muted, pending -> warning,
/// success -> success, danger -> danger, info -> mapBlue,
/// neutral -> muted.
enum StatusTone {
  /// Default neutral tone (e.g., generic status badges).
  neutral,

  /// Rider is ONLINE / connection is healthy.
  online,

  /// Rider is OFFLINE / connection is intentionally down.
  offline,

  /// Pending state (approval, review, queued action).
  pending,

  /// Success state acknowledgement.
  success,

  /// Destructive / failed state acknowledgement.
  danger,

  /// Informational accent (typically map / route related).
  info,
}

/// Compact pill-shaped status indicator used across the rider shell.
///
/// `StatusChip` renders a 999-radius pill whose body uses the tone's soft
/// tint (design §23: status must never rely on a saturated colour alone),
/// with an Ink label for contrast and an 8 px leading dot in the tone's
/// semantic colour. It is the canonical surface for the home connection
/// pill, document statuses on the approval screen, assignment-status badges
/// on offers, and history-list result chips.
class StatusChip extends StatelessWidget {
  /// Creates a status chip showing [label] colored per [tone].
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.showDot = true,
  });

  /// Pill label. Rendered uppercased in [AppTypography.label].
  final String label;

  /// Tone driving the leading-dot colour and the pill's soft tint.
  final StatusTone tone;

  /// Whether to render the 8 px leading dot. Defaults to `true`.
  final bool showDot;

  /// Maps a [StatusTone] to its leading-dot colour.
  static Color dotColorFor(StatusTone tone) {
    switch (tone) {
      case StatusTone.online:
      case StatusTone.success:
        return AppColors.success;
      case StatusTone.offline:
      case StatusTone.neutral:
        return AppColors.muted;
      case StatusTone.pending:
        return AppColors.warning;
      case StatusTone.danger:
        return AppColors.danger;
      case StatusTone.info:
        return AppColors.mapBlue;
    }
  }

  /// Maps a [StatusTone] to its soft pill background.
  ///
  /// Tones without a defined soft tint fall back to the app canvas so the
  /// chip still reads as a distinct surface on a white card.
  static Color backgroundColorFor(StatusTone tone) {
    switch (tone) {
      case StatusTone.online:
      case StatusTone.success:
        return AppColors.successSoft;
      case StatusTone.pending:
        return AppColors.warningSoft;
      case StatusTone.danger:
        return AppColors.errorSoft;
      case StatusTone.offline:
      case StatusTone.neutral:
      case StatusTone.info:
        return AppColors.offWhite;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColorFor(tone),
        borderRadius: BorderRadius.circular(AppDimensions.chipRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showDot) ...<Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColorFor(tone),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label.toUpperCase(),
              style: AppTypography.label.copyWith(color: AppColors.charcoal),
            ),
          ],
        ),
      ),
    );
  }
}
