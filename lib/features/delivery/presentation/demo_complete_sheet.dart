import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/app_button.dart';
import '../application/active_delivery_controller.dart';
import '../domain/delivery_order.dart';
import '../domain/delivery_outcome.dart';

/// Presents the dev-only "demo complete" bottom sheet for [order]
/// (R16).
///
/// Renders a single big black "Complete demo delivery" button that
/// calls [ActiveDeliveryController.deliverWithDemoMode].
///
/// Behaviour:
/// - In production builds (`Env.enableDevAffordances == false`) the
///   sheet does NOT render at all and returns
///   [DeliveryOutcomeCancelled] immediately. R16.3 forbids any path
///   that surfaces this affordance in prod.
/// - On success the sheet pops with [DeliveryOutcomeDelivered].
/// - On backend "demo mode disabled" / generic failure the sheet
///   stays open and renders the inline error (R16.4).
Future<DeliveryOutcome> showDemoCompleteSheet(
  BuildContext context,
  DeliveryOrder order, {
  required Env env,
}) async {
  if (!env.enableDevAffordances) {
    return const DeliveryOutcomeCancelled();
  }

  final DeliveryOutcome? outcome = await showAppBottomSheet<DeliveryOutcome>(
    context,
    initialChildSize: 0.48,
    builder: (BuildContext sheetContext) =>
        _DemoCompleteSheetBody(order: order),
  );
  return outcome ?? const DeliveryOutcomeCancelled();
}

class _DemoCompleteSheetBody extends ConsumerStatefulWidget {
  const _DemoCompleteSheetBody({required this.order});

  final DeliveryOrder order;

  @override
  ConsumerState<_DemoCompleteSheetBody> createState() =>
      _DemoCompleteSheetBodyState();
}

class _DemoCompleteSheetBodyState
    extends ConsumerState<_DemoCompleteSheetBody> {
  String? _inlineError;

  Future<void> _onComplete() async {
    final ActiveDeliveryController controller = ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider);
    final NavigatorState navigator = Navigator.of(context);

    final DeliveryResult result = await controller.deliverWithDemoMode(
      widget.order.orderId,
    );

    if (!navigator.mounted) return;
    switch (result) {
      case DeliveryResultSuccess(orderEarning: final double earnedAmount):
        navigator.pop<DeliveryOutcome>(
          DeliveryOutcomeDelivered(
            orderId: widget.order.orderId,
            earnedAmount: earnedAmount,
            // Total today is computed by the home dashboard refresh
            // that the completion summary sheet kicks off; we pass
            // the per-order earning here so the summary sheet has
            // something sensible until the refresh lands.
            totalToday: earnedAmount,
          ),
        );
      case DeliveryResultStale(message: final String message):
        setState(() => _inlineError = message);
      case DeliveryResultFailure(message: final String message):
        // R16.4 — surface backend "demo mode disabled" copy verbatim.
        setState(() => _inlineError = message);
      case DeliveryResultInvalidOtp(message: final String message):
      case DeliveryResultOtpExpired(message: final String message):
      case DeliveryResultProofFailed(message: final String message):
        setState(() => _inlineError = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ActiveDeliveryController controller = ref
        .watch<ActiveDeliveryController>(activeDeliveryControllerProvider);
    final bool busy = controller.isBusy;

    return AppSheetScaffold(
      title: 'Demo complete',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Bypass OTP and proof photo. Available in dev builds only.',
            style: AppTypography.body.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          if (_inlineError != null) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.danger,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _inlineError!,
                      style: AppTypography.label.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          AppButton(
            label: 'Complete demo delivery',
            isLoading: busy,
            onPressed: busy ? null : _onComplete,
          ),
        ],
      ),
    );
  }
}
