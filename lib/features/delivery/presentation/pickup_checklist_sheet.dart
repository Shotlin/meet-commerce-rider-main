import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/app_button.dart';
import '../application/active_delivery_controller.dart';
import '../application/pickup_session_controller.dart';
import '../domain/pickup_session.dart';

/// Presents the post-scan pickup checklist for [orderId] (items 5 & 7):
/// product name/image/variant/quantity — no price anywhere, by
/// construction of the backend response, not by hiding fields here —
/// plus customer/address/instructions, and a per-item checklist gating
/// "Confirm Pickup" (`markPickedUp`).
///
/// Returns `true` when pickup was confirmed, `false`/`null` when the
/// rider dismissed the sheet without confirming (they can re-open it
/// from the pickup-batch list — the order stays `verified` in
/// [PickupSessionController] either way).
Future<bool?> showPickupChecklistSheet(
  BuildContext context,
  String orderId,
  PickupVerification verification,
) {
  return showAppBottomSheet<bool>(
    context,
    initialChildSize: 0.82,
    isDismissible: false,
    builder: (BuildContext sheetContext) =>
        _PickupChecklistBody(orderId: orderId, verification: verification),
  );
}

class _PickupChecklistBody extends ConsumerStatefulWidget {
  const _PickupChecklistBody({
    required this.orderId,
    required this.verification,
  });

  final String orderId;
  final PickupVerification verification;

  @override
  ConsumerState<_PickupChecklistBody> createState() =>
      _PickupChecklistBodyState();
}

class _PickupChecklistBodyState extends ConsumerState<_PickupChecklistBody> {
  late final List<bool> _checked = List<bool>.filled(
    widget.verification.items.length,
    false,
  );
  bool _busy = false;
  String? _error;

  bool get _allChecked => _checked.isEmpty || _checked.every((bool v) => v);

  Future<void> _onConfirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final ActiveDeliveryController active = ref.read(
      activeDeliveryControllerProvider,
    );
    final NavigatorState navigator = Navigator.of(context);

    try {
      final DeliveryResult result = await active.markPickedUp(widget.orderId);
      if (!navigator.mounted) return;
      switch (result) {
        case DeliveryResultSuccess():
          ref
              .read(pickupSessionControllerProvider)
              .markPickedUp(widget.orderId);
          navigator.pop<bool>(true);
        case DeliveryResultStale(message: final String message):
          setState(() => _error = message);
        case DeliveryResultFailure(message: final String message):
          setState(() => _error = message);
        case DeliveryResultInvalidOtp():
        case DeliveryResultOtpExpired():
        case DeliveryResultProofFailed():
          // Not produced by markPickedUp.
          setState(() => _error = 'Could not confirm pickup');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PickupVerification v = widget.verification;
    final ScrollController? primary = PrimaryScrollController.maybeOf(context);

    // The order is already VERIFIED server-side the moment this sheet
    // opens — a stray system back-gesture must not be able to silently
    // dismiss it with nothing confirmed, leaving the rider stuck (no
    // scan status changes, but no way back into this checklist either).
    // Only the explicit close button or "Confirm Pickup" may close it;
    // pickup_batch_screen.dart's row tap is the recovery path for
    // reopening this same checklist later if the rider does use close.
    return PopScope(
      canPop: false,
      child: AppSheetScaffold(
        title: 'Order ${v.orderNumber}',
        trailing: IconButton(
          icon: const Icon(Icons.close, color: AppColors.muted),
          onPressed: () => Navigator.of(context).pop<bool>(false),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Everything above the CTA lives in one Flexible scroll region so
            // the confirm button is a sticky action zone (design §5): a tall
            // customer card (long address, instructions) can never squeeze the
            // button out of the sheet or overflow the column.
            Flexible(
              child: SingleChildScrollView(
                controller: primary,
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _CustomerCard(verification: v),
                    const SizedBox(height: AppDimensions.lg),
                    Text(
                      'Items to collect',
                      style: AppTypography.label.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.sm),
                    for (int i = 0; i < v.items.length; i++)
                      _ChecklistItemTile(
                        item: v.items[i],
                        value: _checked[i],
                        onChanged: _busy
                            ? null
                            : (bool value) =>
                                  setState(() => _checked[i] = value),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.lg),
            AppButton(
              label: 'Confirm Pickup',
              isLoading: _busy,
              onPressed: _allChecked && !_busy ? _onConfirm : null,
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppDimensions.md),
              Text(
                _error!,
                style: AppTypography.body.copyWith(color: AppColors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.verification});

  final PickupVerification verification;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.person_outline,
                size: 18,
                color: AppColors.charcoal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  verification.customerName,
                  style: AppTypography.body.copyWith(color: AppColors.charcoal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (verification.customerPhone.isNotEmpty)
                Text(
                  verification.customerPhone,
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
            ],
          ),
          if (verification.addressLine.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: AppColors.charcoal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verification.addressLine,
                    style: AppTypography.micro.copyWith(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ],
          if ((verification.deliveryInstructions ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppColors.charcoal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verification.deliveryInstructions!,
                    style: AppTypography.micro.copyWith(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChecklistItemTile extends StatelessWidget {
  const _ChecklistItemTile({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  final PickupChecklistItem item;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: item.image != null && item.image!.isNotEmpty
                    ? Image.network(
                        item.image!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: AppColors.offWhite),
                      )
                    : const ColoredBox(
                        color: AppColors.offWhite,
                        child: Icon(
                          Icons.image_outlined,
                          size: 18,
                          color: AppColors.muted,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${item.quantity} × ${item.name}',
                    style: AppTypography.body.copyWith(
                      color: AppColors.charcoal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((item.variant ?? '').isNotEmpty)
                    Text(
                      item.variant!,
                      style: AppTypography.micro.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.white,
              activeTrackColor: AppColors.black,
              inactiveTrackColor: AppColors.border,
            ),
          ],
        ),
      ),
    );
  }
}
