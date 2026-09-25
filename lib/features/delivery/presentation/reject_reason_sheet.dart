import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../data/delivery_api.dart' show RejectReason;

/// Presents the nested reject-reason picker.
///
/// Returns the chosen [RejectReason] when the rider taps a row,
/// `null` if the rider dismisses the sheet without choosing.
Future<RejectReason?> showRejectReasonSheet(BuildContext context) {
  return showAppBottomSheet<RejectReason>(
    context,
    initialChildSize: 0.48,
    builder: (BuildContext sheetContext) => const _RejectReasonSheetBody(),
  );
}

class _RejectReasonSheetBody extends StatelessWidget {
  const _RejectReasonSheetBody();

  @override
  Widget build(BuildContext context) {
    const List<_ReasonOption> options = <_ReasonOption>[
      _ReasonOption(
        reason: RejectReason.tooFar,
        label: 'Too far',
        description: 'Pickup or drop is outside my range',
      ),
      _ReasonOption(
        reason: RejectReason.vehicleIssue,
        label: 'Vehicle issue',
        description: 'My vehicle is not available right now',
      ),
      _ReasonOption(
        reason: RejectReason.personalReason,
        label: 'Personal reason',
        description: 'On a short break or unavailable',
      ),
      _ReasonOption(
        reason: RejectReason.other,
        label: 'Other',
        description: 'A different reason',
      ),
    ];

    return AppSheetScaffold(
      title: 'Decline this order',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < options.length; i++) ...<Widget>[
            _ReasonRow(option: options[i]),
            if (i != options.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _ReasonOption {
  const _ReasonOption({
    required this.reason,
    required this.label,
    required this.description,
  });

  final RejectReason reason;
  final String label;
  final String description;
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.option});

  final _ReasonOption option;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop<RejectReason>(option.reason),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    option.label,
                    style: AppTypography.body.copyWith(
                      color: AppColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.description,
                    style: AppTypography.micro.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
