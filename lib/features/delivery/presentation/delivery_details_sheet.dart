import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/app_button.dart';
import '../domain/delivery_order.dart';

/// Expanded "complete order details" surface (design §13 swipe-up
/// sheet): both addresses, the full item list, and the customer's
/// delivery notes/instructions.
///
/// Read-only by design — everything actionable (navigate, call,
/// collect, deliver) lives on the delivery card above it.
Future<void> showDeliveryDetailsSheet(
  BuildContext context,
  DeliveryOrder order,
) async {
  await showAppBottomSheet<void>(
    context,
    initialChildSize: 0.72,
    snapSizes: const <double>[0.72],
    builder: (BuildContext sheetContext) => _DeliveryDetailsBody(order: order),
  );
}

class _DeliveryDetailsBody extends StatelessWidget {
  const _DeliveryDetailsBody({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final ScrollController? primary = PrimaryScrollController.maybeOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text(
            'Order #${order.orderNumber}',
            style: AppTypography.heading.copyWith(color: AppColors.charcoal),
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
                _DetailAddress(
                  tag: 'Pickup',
                  title: order.storeAddress.name,
                  subtitle: order.storeAddress.address,
                ),
                const SizedBox(height: 8),
                _DetailAddress(
                  tag: 'Drop',
                  title: order.customerAddress.name,
                  subtitle: order.customerAddress.address,
                ),
                if (_hasNotes) ...<Widget>[
                  const SizedBox(height: 12),
                  _DetailSection(
                    title: 'Delivery notes',
                    child: Text(
                      <String>[
                        ?order.deliveryNotes,
                        ?order.deliveryInstructions,
                      ].join('\n'),
                      style: AppTypography.body.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _DetailSection(
                  title: 'Items (${order.items.length})',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final item in order.items) ...<Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              '${item.quantity} ×',
                              style: AppTypography.label.copyWith(
                                color: AppColors.charcoal,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.name,
                                style: AppTypography.body.copyWith(
                                  color: AppColors.charcoal,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
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

  bool get _hasNotes =>
      (order.deliveryNotes?.isNotEmpty ?? false) ||
      (order.deliveryInstructions?.isNotEmpty ?? false);
}

class _DetailAddress extends StatelessWidget {
  const _DetailAddress({
    required this.tag,
    required this.title,
    required this.subtitle,
  });

  final String tag;
  final String title;
  final String subtitle;

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
            tag,
            style: AppTypography.micro.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: AppTypography.label.copyWith(color: AppColors.charcoal),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.micro.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: AppTypography.label.copyWith(color: AppColors.charcoal),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
