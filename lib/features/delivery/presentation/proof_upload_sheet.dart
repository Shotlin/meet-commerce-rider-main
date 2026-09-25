import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/app_button.dart';
import '../application/active_delivery_controller.dart';
import '../domain/delivery_order.dart';
import '../domain/delivery_outcome.dart';

/// Pluggable image picker so widget tests can inject a fake (R15.1).
typedef ProofImagePicker = Future<File?> Function();

/// Default picker — opens the platform camera via [ImagePicker]. The
/// picker quality is unconstrained (`imageQuality: 100`); compression
/// is handled by [ImageCompressor] on the upload path so the rider
/// keeps their original bytes for any retry.
Future<File?> defaultProofImagePicker() async {
  final ImagePicker picker = ImagePicker();
  try {
    final XFile? captured = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );
    if (captured == null) return null;
    return File(captured.path);
  } catch (_) {
    return null;
  }
}

/// Presents the proof-photo bottom sheet for [order] (R15).
///
/// Behaviour per the task spec:
/// 1. On open the sheet **immediately** launches the camera via
///    [ProofImagePicker]. If the rider cancels (no photo captured)
///    the sheet dismisses with [DeliveryOutcomeCancelled].
/// 2. On photo capture, the sheet compresses via [ImageCompressor],
///    then calls [ActiveDeliveryController.deliverWithProof] which
///    uploads then marks delivered (R15.3). The sheet shows the
///    progress state via the controller's `isBusy` flag.
/// 3. On success the sheet dismisses with [DeliveryOutcomeDelivered].
/// 4. On upload failure (`DeliveryResultProofFailed`) the sheet
///    keeps the captured photo, surfaces an inline retry banner, and
///    stays open (R15.4).
/// 5. On stale order / generic failure the sheet dismisses with
///    [DeliveryOutcomeFailed].
Future<DeliveryOutcome> showProofUploadSheet(
  BuildContext context,
  DeliveryOrder order, {
  ProofImagePicker imagePicker = defaultProofImagePicker,
}) async {
  final DeliveryOutcome? result = await showAppBottomSheet<DeliveryOutcome>(
    context,
    initialChildSize: 0.82,
    builder: (BuildContext sheetContext) =>
        _ProofUploadSheetBody(order: order, imagePicker: imagePicker),
  );
  return result ?? const DeliveryOutcomeCancelled();
}

class _ProofUploadSheetBody extends ConsumerStatefulWidget {
  const _ProofUploadSheetBody({required this.order, required this.imagePicker});

  final DeliveryOrder order;
  final ProofImagePicker imagePicker;

  @override
  ConsumerState<_ProofUploadSheetBody> createState() =>
      _ProofUploadSheetBodyState();
}

class _ProofUploadSheetBodyState extends ConsumerState<_ProofUploadSheetBody> {
  File? _preview;
  bool _showRetry = false;
  bool _initialPickStarted = false;

  @override
  void initState() {
    super.initState();
    // R15.1: open the camera as soon as the sheet mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialPickStarted) return;
      _initialPickStarted = true;
      unawaited(_pickFirstPhoto());
    });
  }

  Future<void> _pickFirstPhoto() async {
    final NavigatorState navigator = Navigator.of(context);
    final File? captured = await widget.imagePicker();
    if (!navigator.mounted) return;
    if (captured == null) {
      // Rider cancelled out of the camera — dismiss sheet.
      navigator.pop<DeliveryOutcome>(const DeliveryOutcomeCancelled());
      return;
    }
    setState(() {
      _preview = captured;
      _showRetry = false;
    });
  }

  Future<void> _pickAgain() async {
    final File? captured = await widget.imagePicker();
    if (!mounted || captured == null) return;
    setState(() {
      _preview = captured;
      _showRetry = false;
    });
  }

  Future<void> _upload() async {
    final File? source = _preview;
    if (source == null) return;

    final ActiveDeliveryController controller = ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider);
    final ImageCompressor compressor = ref.read<ImageCompressor>(
      imageCompressorProvider,
    );
    final NavigatorState navigator = Navigator.of(context);

    File compressed;
    try {
      compressed = await compressor.compress(source);
    } catch (_) {
      compressed = source;
    }

    final DeliveryResult result = await controller.deliverWithProof(
      widget.order.orderId,
      compressed,
    );

    if (!navigator.mounted) return;
    switch (result) {
      case DeliveryResultSuccess(orderEarning: final double earned):
        navigator.pop<DeliveryOutcome>(
          DeliveryOutcomeDelivered(
            orderId: widget.order.orderId,
            earnedAmount: earned,
            totalToday: earned,
          ),
        );
      case DeliveryResultStale(message: final String message):
      case DeliveryResultFailure(message: final String message):
      case DeliveryResultInvalidOtp(message: final String message):
      case DeliveryResultOtpExpired(message: final String message):
        navigator.pop<DeliveryOutcome>(DeliveryOutcomeFailed(message));
      case DeliveryResultProofFailed():
        // R15.4 — keep the sheet open, show the retry banner.
        setState(() => _showRetry = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ActiveDeliveryController controller = ref
        .watch<ActiveDeliveryController>(activeDeliveryControllerProvider);
    final bool busy = controller.isBusy;

    return AppSheetScaffold(
      title: 'Proof photo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Take a photo of the delivery to confirm completion.',
            style: AppTypography.body.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: _preview == null
                ? const _LoadingPreview()
                : _ImagePreview(file: _preview!),
          ),
          const SizedBox(height: 12),
          if (_showRetry) ...<Widget>[
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
                      'Could not upload photo. Try again',
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
          if (_preview != null) ...<Widget>[
            AppButton(
              label: _showRetry ? 'Retry upload & deliver' : 'Upload & deliver',
              isLoading: busy,
              onPressed: busy ? null : _upload,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Retake photo',
              variant: AppButtonVariant.secondary,
              onPressed: busy ? null : _pickAgain,
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingPreview extends StatelessWidget {
  const _LoadingPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.charcoal,
          ),
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(file, fit: BoxFit.cover, width: double.infinity),
    );
  }
}
