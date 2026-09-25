import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../delivery/domain/delivery_history_entry.dart';

/// Full detail for one history entry (design §19 "tap opens full
/// detail"): order info, delivery timing, earning, payment context,
/// and the status. Read-only — history is a record, not a workflow.
Future<void> showDeliveryHistoryDetailSheet(
  BuildContext context,
  DeliveryHistoryEntry entry,
) async {
  await showAppBottomSheet<void>(
    context,
    initialChildSize: 0.66,
    snapSizes: const <double>[0.66],
    builder: (BuildContext sheetContext) =>
        _DeliveryHistoryDetailBody(entry: entry),
  );
}

class _DeliveryHistoryDetailBody extends StatelessWidget {
  const _DeliveryHistoryDetailBody({required this.entry});

  final DeliveryHistoryEntry entry;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final DateFormat _dateTime = DateFormat('d MMM yyyy, h:mm a');

  String _formatWhen(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return _dateTime.format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  StatusTone _toneFor(String status) {
    switch (status) {
      case 'DELIVERED':
        return StatusTone.success;
      case 'CANCELLED':
        return StatusTone.danger;
      default:
        return StatusTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ScrollController? primary = PrimaryScrollController.maybeOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.orderNumber.isEmpty
                      ? 'Delivery'
                      : '#${entry.orderNumber.toUpperCase()}',
                  style: AppTypography.heading.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
              ),
              StatusChip(label: entry.status, tone: _toneFor(entry.status)),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: primary,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _DetailBlock(
                  label: 'EARNING',
                  value: _money.format(entry.earnings),
                  valueColor: AppColors.success,
                ),
                const SizedBox(height: 8),
                _DetailBlock(
                  label: 'COMPLETED',
                  value: _formatWhen(entry.completedAt),
                ),
                if (entry.customerArea != null &&
                    entry.customerArea!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  _DetailBlock(
                    label: 'DELIVERY AREA',
                    value: entry.customerArea!,
                  ),
                ],
                const SizedBox(height: 16),
                AppButton(
                  label: 'Close',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: AppTypography.micro.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.label.copyWith(
              color: valueColor ?? AppColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}
