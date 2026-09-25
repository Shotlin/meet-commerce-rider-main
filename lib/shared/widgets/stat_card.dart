import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';

/// White surface displaying a single labeled metric.
///
/// `StatCard` renders the rider app's go-to "label + value" tile: an
/// uppercase muted micro label, a large title-typography value, and an
/// optional trailing icon tinted with [accent]. Used across the home
/// dashboard (today's earnings, deliveries, rating), the earnings
/// breakdown, and the profile vehicle/document summary.
class StatCard extends StatelessWidget {
  /// Creates a stat card showing [label] above [value], optionally with a
  /// trailing [icon] colored [accent].
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent,
  });

  /// Uppercase label rendered in muted micro typography.
  final String label;

  /// Primary metric rendered in title typography.
  final String value;

  /// Optional trailing icon (e.g., trend up/down).
  final IconData? icon;

  /// Optional accent color applied to [icon]. Defaults to charcoal.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label.toUpperCase(),
                    style: AppTypography.micro.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: AppTypography.title.copyWith(
                      color: AppColors.charcoal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (icon != null) ...<Widget>[
              const SizedBox(width: 12),
              Icon(icon, size: 22, color: accent ?? AppColors.charcoal),
            ],
          ],
        ),
      ),
    );
  }
}
