import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/realtime/socket_client.dart';
import '../../../core/realtime/socket_events.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/app_button.dart';
import '../../home/application/home_dashboard_controller.dart';
import '../application/active_delivery_controller.dart';

/// Presents the celebratory completion summary sheet (R14.4 / R15.3 /
/// R16 — final stage of the delivery flow).
///
/// Sheet body:
/// - "Delivered ✅" hero copy.
/// - [earnedAmount] in [AppTypography.display].
/// - Order number and customer name rows.
/// - "Today's total" footer rendering [totalEarningsToday].
/// - Single "Got it" primary button to dismiss.
///
/// On dismiss the parent flow runs the side effects required by R14.4
/// — emit `order:untrack`, refresh stats + earnings, clear the active
/// delivery — exactly once. The work is fired regardless of whether
/// the rider taps the button or backs out via the system gesture, so
/// no path can leak the active delivery into the home dashboard.
Future<void> showCompletionSummarySheet(
  BuildContext context, {
  required String orderId,
  required double earnedAmount,
  required String orderNumber,
  required String customerName,
  required double totalEarningsToday,
}) async {
  await showAppBottomSheet<void>(
    context,
    initialChildSize: 0.48,
    isDismissible: false,
    builder: (BuildContext sheetContext) => _CompletionSummaryBody(
      orderId: orderId,
      earnedAmount: earnedAmount,
      orderNumber: orderNumber,
      customerName: customerName,
      totalEarningsToday: totalEarningsToday,
    ),
  );
}

class _CompletionSummaryBody extends ConsumerStatefulWidget {
  const _CompletionSummaryBody({
    required this.orderId,
    required this.earnedAmount,
    required this.orderNumber,
    required this.customerName,
    required this.totalEarningsToday,
  });

  final String orderId;
  final double earnedAmount;
  final String orderNumber;
  final String customerName;
  final double totalEarningsToday;

  @override
  ConsumerState<_CompletionSummaryBody> createState() =>
      _CompletionSummaryBodyState();
}

class _CompletionSummaryBodyState
    extends ConsumerState<_CompletionSummaryBody> {
  /// Latch so the side effects fire exactly once even if the dispose
  /// path runs alongside an in-flight tap. Required to satisfy the
  /// "doesn't double-emit" expectation in the test for this sheet.
  bool _sideEffectsRan = false;

  void _runSideEffectsOnce() {
    if (_sideEffectsRan) return;
    _sideEffectsRan = true;

    final SocketClient socket = ref.read<SocketClient>(socketClientProvider);
    socket.emit(SocketEvents.orderUntrack, <String, dynamic>{
      'orderId': widget.orderId,
    });

    // Refresh stats + earnings so the home dashboard reflects the
    // newly-credited delivery (R14.4).
    final HomeDashboardController dashboard = ref.read<HomeDashboardController>(
      homeDashboardControllerProvider,
    );
    unawaited(dashboard.refreshStats());
    unawaited(dashboard.refreshEarningsToday());

    // Clear the just-completed delivery from the controller so the
    // home shell stops pinning the active-delivery card.
    ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider)
        .clearActiveDelivery();
  }

  Future<void> _onGotIt() async {
    final NavigatorState navigator = Navigator.of(context);
    _runSideEffectsOnce();
    if (!navigator.mounted) return;
    navigator.pop<void>();
  }

  @override
  void dispose() {
    // If the rider somehow dismissed the sheet without tapping "Got
    // it" (e.g. via a future system gesture path), still run the
    // side effects so the active delivery is cleared.
    _runSideEffectsOnce();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool commissionEnabled =
        ref.watch(riderProfileProvider).asData?.value.commissionEnabled ?? true;
    return AppSheetScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Hero copy.
          Text(
            'Delivered ✅',
            style: AppTypography.title.copyWith(color: AppColors.charcoal),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Earned amount card.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (commissionEnabled) ...<Widget>[
                  Text(
                    'You earned',
                    style: AppTypography.label.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${widget.earnedAmount.toStringAsFixed(0)}',
                    style: AppTypography.display.copyWith(
                      color: AppColors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _SummaryRow(label: 'Order', value: '#${widget.orderNumber}'),
                const SizedBox(height: 8),
                _SummaryRow(label: 'Customer', value: widget.customerName),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Today's total footer.
          if (commissionEnabled) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    "Today's total",
                    style: AppTypography.label.copyWith(color: AppColors.muted),
                  ),
                ),
                Text(
                  '₹${widget.totalEarningsToday.toStringAsFixed(0)}',
                  style: AppTypography.heading.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          AppButton(label: 'Got it', onPressed: _onGotIt),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: AppTypography.label.copyWith(color: AppColors.muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.body.copyWith(color: AppColors.charcoal),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
