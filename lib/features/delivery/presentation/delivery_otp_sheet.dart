import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_constants.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/app_button.dart';
import '../application/active_delivery_controller.dart';
import '../domain/delivery_order.dart';
import '../domain/delivery_outcome.dart';
import 'proof_upload_sheet.dart';

/// Presents the delivery-confirmation sheet for [order].
///
/// The customer is shown a 4-digit delivery code in their FreshCuts app
/// (and by notification when the rider picks the order up). The rider
/// asks for it at the door and types it here; the backend verifies it —
/// the code is never sent to the rider's app.
///
/// - **Confirm delivery** calls [ActiveDeliveryController.deliverWithOtp]
///   and pops [DeliveryOutcomeDelivered] on success. A wrong code keeps
///   the sheet open with an inline error.
/// - **Resend code** asks the backend to send the customer a fresh code.
/// - **Use a photo instead** is the fallback when the customer cannot
///   share the code: it hands over to [showProofUploadSheet] and returns
///   whatever outcome that produces.
Future<DeliveryOutcome> showDeliveryOtpSheet(
  BuildContext context,
  DeliveryOrder order,
) async {
  final DeliveryOutcome? outcome = await showAppBottomSheet<DeliveryOutcome>(
    context,
    initialChildSize: 0.74,
    builder: (BuildContext sheetContext) =>
        _DeliveryOtpSheetBody(order: order, rootContext: context),
  );
  return outcome ?? const DeliveryOutcomeCancelled();
}

class _DeliveryOtpSheetBody extends ConsumerStatefulWidget {
  const _DeliveryOtpSheetBody({required this.order, required this.rootContext});

  final DeliveryOrder order;

  /// A context that outlives this sheet, used to open the proof sheet after
  /// this one has been popped.
  final BuildContext rootContext;

  @override
  ConsumerState<_DeliveryOtpSheetBody> createState() =>
      _DeliveryOtpSheetBodyState();
}

class _DeliveryOtpSheetBodyState extends ConsumerState<_DeliveryOtpSheetBody> {
  final TextEditingController _controller = TextEditingController();
  String? _inlineError;
  String? _inlineNotice;
  bool _resending = false;

  bool get _complete => _controller.text.trim().length == _codeLength;

  static const int _codeLength = AppConstants.deliveryOtpLength;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    if (!_complete) return;
    final ActiveDeliveryController controller = ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider);
    final NavigatorState navigator = Navigator.of(context);
    setState(() {
      _inlineError = null;
      _inlineNotice = null;
    });

    final DeliveryResult result = await controller.deliverWithOtp(
      widget.order.orderId,
      _controller.text,
    );
    if (!navigator.mounted || !mounted) return;

    switch (result) {
      case DeliveryResultSuccess(orderEarning: final double earnedAmount):
        navigator.pop<DeliveryOutcome>(
          DeliveryOutcomeDelivered(
            orderId: widget.order.orderId,
            earnedAmount: earnedAmount,
            totalToday: earnedAmount,
          ),
        );
      case DeliveryResultInvalidOtp(message: final String message):
        _controller.clear();
        setState(() => _inlineError = message);
      case DeliveryResultStale(message: final String message):
      case DeliveryResultFailure(message: final String message):
      case DeliveryResultOtpExpired(message: final String message):
      case DeliveryResultProofFailed(message: final String message):
        setState(() => _inlineError = message);
    }
  }

  Future<void> _onResend() async {
    if (_resending) return;
    setState(() {
      _resending = true;
      _inlineError = null;
      _inlineNotice = null;
    });
    final String? failure = await ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider)
        .resendDeliveryOtp(widget.order.orderId);
    if (!mounted) return;
    setState(() {
      _resending = false;
      if (failure == null) {
        _inlineNotice = 'A new code was sent to the customer';
        _controller.clear();
      } else {
        _inlineError = failure;
      }
    });
  }

  void _onUsePhoto() {
    final NavigatorState navigator = Navigator.of(context);
    final BuildContext rootContext = widget.rootContext;
    final DeliveryOrder order = widget.order;
    // Close this sheet, then open the proof sheet and report its outcome
    // through the same caller-visible channel.
    navigator.pop<DeliveryOutcome>(const DeliveryOutcomeCancelled());
    unawaited(showProofUploadSheet(rootContext, order));
  }

  @override
  Widget build(BuildContext context) {
    final ActiveDeliveryController controller = ref
        .watch<ActiveDeliveryController>(activeDeliveryControllerProvider);
    final bool busy = controller.isBusy;
    final String customer = widget.order.customerAddress.name.isEmpty
        ? 'the customer'
        : widget.order.customerAddress.name;

    // Scrollable: on a short phone with the keyboard open the code field,
    // actions and fallback links must stay reachable rather than clip.
    return AppSheetScaffold(
      title: 'Confirm delivery',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Ask $customer for the $_codeLength-digit delivery code shown in '
              'their FreshCuts app.',
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('deliveryOtpField'),
              controller: _controller,
              autofocus: true,
              enabled: !busy,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: _codeLength,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: AppTypography.display.copyWith(letterSpacing: 12),
              onChanged: (_) => setState(() => _inlineError = null),
              onSubmitted: (_) => unawaited(_onConfirm()),
              decoration: InputDecoration(
                counterText: '',
                hintText: '• ' * _codeLength,
                filled: true,
                fillColor: AppColors.offWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.brand,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            if (_inlineError != null) ...<Widget>[
              const SizedBox(height: 12),
              _Banner(
                key: const Key('deliveryOtpError'),
                message: _inlineError!,
                color: AppColors.danger,
                soft: AppColors.errorSoft,
                icon: Icons.error_outline,
              ),
            ],
            if (_inlineNotice != null) ...<Widget>[
              const SizedBox(height: 12),
              _Banner(
                key: const Key('deliveryOtpNotice'),
                message: _inlineNotice!,
                color: AppColors.success,
                soft: AppColors.successSoft,
                icon: Icons.check_circle_outline,
              ),
            ],
            const SizedBox(height: 16),
            AppButton(
              label: 'Confirm delivery',
              isLoading: busy,
              onPressed: (busy || !_complete)
                  ? null
                  : () => unawaited(_onConfirm()),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('deliveryOtpResend'),
              onPressed: (busy || _resending)
                  ? null
                  : () => unawaited(_onResend()),
              child: Text(
                _resending ? 'Sending…' : 'Resend code to customer',
                style: AppTypography.label.copyWith(color: AppColors.graphite),
              ),
            ),
            TextButton(
              key: const Key('deliveryOtpUsePhoto'),
              onPressed: busy ? null : _onUsePhoto,
              child: Text(
                "Customer can't share the code? Use a photo",
                style: AppTypography.label.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.message,
    required this.color,
    required this.soft,
    required this.icon,
  });

  final String message;
  final Color color;
  final Color soft;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.label.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
