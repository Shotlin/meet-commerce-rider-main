import 'package:flutter/material.dart';

import '../../core/config/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_typography.dart';

/// Top-of-screen banner shown when the device is offline.
///
/// `AppOfflineBanner` overlays a [MaterialBanner]-style strip above
/// [child] when [isOffline] is true. The strip uses [AppMotion.fast]
/// driven [AnimatedSlide] and [AnimatedOpacity] so connectivity flips
/// don't slam the layout. Copy is pulled from
/// [AppConstants.offlineBannerCopy] (R27.2).
class AppOfflineBanner extends StatelessWidget {
  /// Creates an offline banner overlay around [child] toggled by
  /// [isOffline].
  const AppOfflineBanner({
    super.key,
    required this.isOffline,
    required this.child,
  });

  /// Whether the offline strip is visible.
  final bool isOffline;

  /// Subtree the banner sits above.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: IgnorePointer(
              ignoring: !isOffline,
              child: AnimatedSlide(
                offset: isOffline ? Offset.zero : const Offset(0, -1),
                duration: AppMotion.fast,
                curve: AppMotion.easing,
                child: AnimatedOpacity(
                  opacity: isOffline ? 1 : 0,
                  duration: AppMotion.fast,
                  curve: AppMotion.easing,
                  child: const _OfflineStrip(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip();

  @override
  Widget build(BuildContext context) {
    // Reconnecting/offline is a warning-tone state (design §23): amber strip,
    // Ink copy, warning-coloured icon — never a colour-only signal.
    return Material(
      color: AppColors.warningSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.lg,
          vertical: AppDimensions.md,
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.wifi_off, size: 16, color: AppColors.warning),
            const SizedBox(width: AppDimensions.sm),
            Expanded(
              child: Text(
                AppConstants.offlineBannerCopy,
                style: AppTypography.label.copyWith(color: AppColors.charcoal),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
