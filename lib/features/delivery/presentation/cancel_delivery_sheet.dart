import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../data/delivery_api.dart' show CancelDeliveryReason;

/// Presents the cancel-delivery reason picker, shown when the customer
/// refuses the order at the door or can't be reached.
///
/// Returns the chosen [CancelDeliveryReason] when the rider taps a
/// row, `null` if the rider dismisses the sheet without choosing.
Future<CancelDeliveryReason?> showCancelDeliverySheet(BuildContext context) {
  return showAppBottomSheet<CancelDeliveryReason>(
    context,
    initialChildSize: 0.48,
    builder: (BuildContext sheetContext) => const _CancelDeliverySheetBody(),
  );
}

class _CancelDeliverySheetBody extends StatelessWidget {
  const _CancelDeliverySheetBody();

  @override
  Widget build(BuildContext context) {
    const List<_ReasonOption> options = <_ReasonOption>[
      _ReasonOption(
        reason: CancelDeliveryReason.customerRefused,
        label: 'Customer refused the order',
        description: 'They declined to accept it at the door',
      ),
      _ReasonOption(
        reason: CancelDeliveryReason.customerUnreachable,
        label: "Customer isn't responding",
        description: "They aren't answering calls or the door",
      ),
      _ReasonOption(
        reason: CancelDeliveryReason.customerNotHome,
        label: 'Customer not at the address',
        description: "They aren't at the delivery location",
      ),
      _ReasonOption(
        reason: CancelDeliveryReason.other,
        label: 'Other',
        description: 'A different reason',
      ),
    ];

    return AppSheetScaffold(
      title: 'Cancel this delivery',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'The order will be cancelled and the customer will be notified.',
            style: AppTypography.micro.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
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

  final CancelDeliveryReason reason;
  final String label;
  final String description;
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.option});

  final _ReasonOption option;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () =>
          Navigator.of(context).pop<CancelDeliveryReason>(option.reason),
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
