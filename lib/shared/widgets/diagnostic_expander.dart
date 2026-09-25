import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Collapsible diagnostic card surfaced after a critical action fails
/// twice in 10 seconds (R27.5).
///
/// Each row is a `(label, value)` pair where the label is rendered in
/// [AppTypography.micro] muted and the value in [AppTypography.micro]
/// charcoal. Used by accept/pickup/deliver flows to show the request
/// method/path, Backend code/message, and timestamps to aid manual
/// debugging during demos.
class DiagnosticExpander extends StatelessWidget {
  /// Creates a diagnostic expander with the given [summary] header and
  /// `(label, value)` [rows].
  const DiagnosticExpander({
    super.key,
    required this.summary,
    required this.rows,
  });

  /// Header copy for the [ExpansionTile]; typically "Show details".
  final String summary;

  /// Ordered diagnostic rows. The key is the label, the value is the
  /// content shown next to it.
  final List<MapEntry<String, String>> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        // Strip the default expansion divider so the card reads as a
        // single offWhite surface.
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          collapsedShape: const RoundedRectangleBorder(),
          shape: const RoundedRectangleBorder(),
          backgroundColor: AppColors.offWhite,
          collapsedBackgroundColor: AppColors.offWhite,
          iconColor: AppColors.charcoal,
          collapsedIconColor: AppColors.charcoal,
          title: Text(
            summary,
            style: AppTypography.label.copyWith(color: AppColors.charcoal),
          ),
          children: <Widget>[
            for (final MapEntry<String, String> row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 96,
                      child: Text(
                        row.key,
                        style: AppTypography.micro.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        row.value,
                        style: AppTypography.micro.copyWith(
                          color: AppColors.charcoal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
