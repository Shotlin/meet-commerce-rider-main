import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Shared empty-state placeholder used across rider screens.
///
/// `EmptyState` renders a centered column with a 48 dp muted icon, a
/// title in [AppTypography.heading], optional muted body, and an
/// optional [action] widget. Used for the home "no offers" surface
/// (R5.5), empty earnings periods, empty history, and empty payouts.
class EmptyState extends StatelessWidget {
  /// Creates an empty-state placeholder with [icon], [title], and an
  /// optional [body] / [action].
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  /// Icon shown above the title; rendered at 48 dp in [AppColors.muted].
  final IconData icon;

  /// Primary copy describing the empty state.
  final String title;

  /// Optional secondary copy giving context or a CTA hint.
  final String? body;

  /// Optional action widget rendered below the body (typically an
  /// `AppButton`).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.heading.copyWith(color: AppColors.charcoal),
            ),
            if (body != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
