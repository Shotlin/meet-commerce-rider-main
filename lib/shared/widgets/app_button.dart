import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';

/// Visual variant for [AppButton].
///
/// Each variant maps to a fixed background/foreground/border combination
/// described in the design system (§5). The mapping is intentionally narrow
/// so the rider app never grows a long tail of bespoke button styles.
enum AppButtonVariant {
  /// Primary action: FreshCuts red surface with white label. Used for the
  /// one action that advances the workflow (Go Online, Accept Order,
  /// Confirm Pickup, Verify & Deliver).
  primary,

  /// Secondary action: white surface with ink label and 1dp border.
  secondary,

  /// Destructive action: error-red surface with white label. Only ever
  /// shown behind an explicit confirmation step (design §5).
  danger,

  /// Confirmatory success action: green surface with white label. Used
  /// sparingly, e.g., a successful state acknowledgement.
  success,
}

/// The single button widget for the Meet Commerce Rider App.
///
/// `AppButton` owns the rider app's visual button language so screens never
/// reach for raw [ElevatedButton] / [OutlinedButton] variants. It enforces
/// the design system's tap-target floor (>= 48 dp tall, 16 dp vertical
/// padding), the 16-radius corner, and the busy-state spinner.
///
/// Used widely across login, OTP, approval, deliver sheets, profile
/// actions, and inline empty/error CTAs.
class AppButton extends StatelessWidget {
  /// Creates a button styled per [variant] with [label] and [onPressed].
  ///
  /// Pass `onPressed: null` to render a disabled button. When [isLoading]
  /// is true the label is replaced with a small inline spinner and the
  /// button is treated as disabled.
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.leadingIcon,
    this.fullWidth = true,
  });

  /// Text shown inside the button.
  final String label;

  /// Pressed callback; pass `null` to render a disabled button.
  final VoidCallback? onPressed;

  /// Visual variant for the button surface and label color.
  final AppButtonVariant variant;

  /// Whether to render the inline loading spinner in place of [label]. The
  /// button is non-interactive while [isLoading] is true.
  final bool isLoading;

  /// Optional leading icon drawn before the [label].
  final IconData? leadingIcon;

  /// Whether the button stretches to its parent's max width. Defaults to
  /// `true` so rider screens get edge-to-edge primary actions.
  final bool fullWidth;

  bool get _enabled => onPressed != null && !isLoading;

  _AppButtonStyle _resolveStyle() {
    switch (variant) {
      case AppButtonVariant.primary:
        return const _AppButtonStyle(
          background: AppColors.brand,
          foreground: AppColors.white,
          borderColor: null,
          pressedOverlay: AppColors.brandPressed,
        );
      case AppButtonVariant.secondary:
        return const _AppButtonStyle(
          background: AppColors.white,
          foreground: AppColors.charcoal,
          borderColor: AppColors.border,
          pressedOverlay: null,
        );
      case AppButtonVariant.danger:
        return const _AppButtonStyle(
          background: AppColors.danger,
          foreground: AppColors.white,
          borderColor: null,
          pressedOverlay: null,
        );
      case AppButtonVariant.success:
        return const _AppButtonStyle(
          background: AppColors.success,
          foreground: AppColors.white,
          borderColor: null,
          pressedOverlay: null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final _AppButtonStyle style = _resolveStyle();

    final Color background = _enabled
        ? style.background
        : style.background.withValues(alpha: 0.5);
    final Color foreground = _enabled
        ? style.foreground
        : style.foreground.withValues(alpha: 0.6);

    final Widget content = isLoading
        ? SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leadingIcon != null) ...<Widget>[
                Icon(leadingIcon, size: 18, color: foreground),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.label.copyWith(color: foreground),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          );

    final BorderRadius radius = BorderRadius.circular(
      AppDimensions.buttonRadius,
    );

    final Widget surface = Material(
      color: background,
      borderRadius: radius,
      child: InkWell(
        onTap: _enabled ? onPressed : null,
        borderRadius: radius,
        splashColor: Colors.transparent,
        // Full-width workflow buttons darken toward the pressed brand shade
        // while held; outlined variants keep the theme's no-ripple rule.
        highlightColor: style.pressedOverlay == null
            ? Colors.transparent
            : style.pressedOverlay!.withValues(alpha: 0.18),
        child: Container(
          // Full-width buttons are workflow actions and use the design's
          // 54 px primary height; inline buttons only need the 48 px
          // accessibility floor.
          constraints: BoxConstraints(
            minHeight: fullWidth
                ? AppDimensions.buttonHeight
                : AppDimensions.touchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: style.borderColor != null
                ? Border.all(
                    color: _enabled
                        ? style.borderColor!
                        : style.borderColor!.withValues(alpha: 0.5),
                    width: 1,
                  )
                : null,
          ),
          child: content,
        ),
      ),
    );

    if (!fullWidth) {
      return surface;
    }
    return SizedBox(width: double.infinity, child: surface);
  }
}

/// Internal record of the resolved colors for an [AppButtonVariant].
class _AppButtonStyle {
  const _AppButtonStyle({
    required this.background,
    required this.foreground,
    required this.borderColor,
    required this.pressedOverlay,
  });

  final Color background;
  final Color foreground;
  final Color? borderColor;

  /// Optional colour painted at low opacity while the finger is down.
  final Color? pressedOverlay;
}
