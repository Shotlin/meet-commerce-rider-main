import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import 'app_button.dart';

/// Shared error-state placeholder used across rider screens.
///
/// `ErrorState` mirrors [EmptyState]'s layout but uses
/// [Icons.error_outline] colored [AppColors.danger] and exposes a
/// `secondary`-variant retry button when [onRetry] is non-null. Used by
/// the dashboard cards, earnings, history, and any list screen whose
/// fetch fails (R5.3, R27.1, R27.4).
class ErrorState extends StatelessWidget {
  /// Creates an error placeholder titled [title] with optional [body]
  /// and optional [onRetry] action.
  const ErrorState({
    super.key,
    required this.title,
    this.body,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  /// Primary copy describing the failure mode.
  final String title;

  /// Optional secondary copy giving the rider a hint of what happened.
  final String? body;

  /// Tapped to re-trigger the failed action. When `null` no button is
  /// rendered.
  final VoidCallback? onRetry;

  /// Label for the retry button. Defaults to "Retry".
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
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
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppDimensions.lg),
              AppButton(
                label: retryLabel,
                variant: AppButtonVariant.primary,
                fullWidth: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
