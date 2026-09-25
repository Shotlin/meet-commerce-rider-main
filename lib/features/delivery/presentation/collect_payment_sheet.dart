import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../domain/collected_payment.dart';
import '../../../core/providers.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery_order.dart';

/// Tolerance (in rupees) the confirm button allows between the recorded
/// cash+UPI split and the order total — mirrors the backend's own
/// paise-rounding tolerance in `delivery.service.js#markDelivered` so the
/// rider never sees the sheet accept a split the backend then rejects.
const double _kCollectionTolerance = 2;

/// UPI payee display name used in the `upi://pay` deep link the rider shows
/// the customer for UPI collection.
///
/// Single source of truth until the backend serves a configured business
/// payee name (Big Phase 14). Do not inline this string anywhere else.
const String DEFAULT_UPI_PAYEE_NAME = 'Meet Commerce';

/// Presents the COD payment-collection bottom sheet for [order]: a UPI QR
/// the rider shows the customer, and two fields recording how much was
/// paid in cash vs. via that QR.
///
/// Returns the confirmed [CollectedPayment], or `null` if the rider
/// dismissed the sheet — callers should treat `null` as "do not proceed
/// to delivery confirmation".
///
/// Only meaningful for Cash on Delivery orders; callers gate on
/// `order.paymentMethod == 'COD'` before invoking this (Wallet/Online
/// orders are already paid and skip this step entirely).
Future<CollectedPayment?> showCollectPaymentSheet(
  BuildContext context,
  DeliveryOrder order,
) {
  return showAppBottomSheet<CollectedPayment>(
    context,
    initialChildSize: 0.86,
    snapSizes: const <double>[0.86],
    enableDrag: false,
    builder: (BuildContext sheetContext) =>
        _CollectPaymentSheetBody(order: order),
  );
}

class _CollectPaymentSheetBody extends ConsumerStatefulWidget {
  const _CollectPaymentSheetBody({required this.order});

  final DeliveryOrder order;

  @override
  ConsumerState<_CollectPaymentSheetBody> createState() =>
      _CollectPaymentSheetBodyState();
}

class _CollectPaymentSheetBodyState
    extends ConsumerState<_CollectPaymentSheetBody> {
  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _upiController = TextEditingController();

  @override
  void dispose() {
    _cashController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  double get _cash => double.tryParse(_cashController.text) ?? 0;
  double get _upi => double.tryParse(_upiController.text) ?? 0;
  double get _remaining => widget.order.totalAmount - (_cash + _upi);
  bool get _isBalanced => _remaining.abs() <= _kCollectionTolerance;

  bool _posting = false;
  String? _errorMessage;

  /// Confirms the split: persists it server-side (Big Phase 14) before
  /// popping. The deterministic `collection-{orderId}` idempotency key
  /// makes a retry a replay, never a duplicate posting. On mismatch or
  /// transport failure the rider stays on the sheet with the backend's
  /// message (requirement §14: "remain on collection screen").
  Future<void> _onConfirm() async {
    if (_posting) return;
    setState(() {
      _posting = true;
      _errorMessage = null;
    });

    final NavigatorState navigator = Navigator.of(context);
    try {
      await ref
          .read<DeliveryRepository>(deliveryRepositoryProvider)
          .postCollection(
            widget.order.orderId,
            cashAmount: _cash,
            upiAmount: _upi,
            idempotencyKey: 'collection-${widget.order.orderId}',
          );
      if (!navigator.mounted) return;
      navigator.pop<CollectedPayment>(
        CollectedPayment(cashCollected: _cash, upiCollected: _upi),
      );
    } on ApiException catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'postCollection(${widget.order.orderId}) failed: '
        '${e.backendCode ?? 'no-code'} ${e.message}',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _posting = false;
        _errorMessage = e.message;
      });
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'postCollection(${widget.order.orderId}) unexpected error',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _posting = false;
        _errorMessage = 'Could not record the collection. Try again';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? businessUpiId = ref
        .watch(riderProfileProvider)
        .asData
        ?.value
        .businessUpiId;

    return AppSheetScaffold(
      title: 'Collect payment',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Order total: ₹${widget.order.totalAmount.toStringAsFixed(2)}',
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            if (businessUpiId != null && businessUpiId.isNotEmpty) ...<Widget>[
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: QrImageView(
                      data: _upiPaymentUri(businessUpiId, widget.order),
                      size: 176,
                      backgroundColor: AppColors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Show this QR if the customer wants to pay via UPI',
                textAlign: TextAlign.center,
                style: AppTypography.label.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: <Widget>[
                Expanded(
                  child: AppTextField(
                    controller: _cashController,
                    label: 'Cash collected',
                    hint: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _upiController,
                    label: 'UPI collected',
                    hint: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _isBalanced
                  ? 'Total collected matches the order total'
                  : _remaining > 0
                  ? '₹${_remaining.toStringAsFixed(2)} still remaining'
                  : '₹${(-_remaining).toStringAsFixed(2)} more than the order total',
              style: AppTypography.micro.copyWith(
                color: _isBalanced ? AppColors.success : AppColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null) ...<Widget>[
              Text(
                _errorMessage!,
                style: AppTypography.micro.copyWith(color: AppColors.danger),
              ),
              const SizedBox(height: 8),
            ],
            AppButton(
              label: 'Confirm & continue',
              isLoading: _posting,
              onPressed: _isBalanced && !_posting ? _onConfirm : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a standard `upi://pay` deep-link URI for [order]'s total.
  ///
  /// [DEFAULT_UPI_PAYEE_NAME] is the display name the customer's UPI app
  /// shows next to the amount. The Meet Commerce backend does not yet expose
  /// a configured payee name, so this stays a single constant until the
  /// collections work in Big Phase 14 serves the real business payee name.
  static String _upiPaymentUri(String upiId, DeliveryOrder order) {
    final Uri uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: <String, String>{
        'pa': upiId,
        'pn': DEFAULT_UPI_PAYEE_NAME,
        'am': order.totalAmount.toStringAsFixed(2),
        'cu': 'INR',
        'tn': 'Order ${order.orderNumber}',
      },
    );
    return uri.toString();
  }
}
