import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/permissions/camera_permission_status.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/app_logger.dart';
import '../../../shared/widgets/app_button.dart';
import '../application/active_delivery_controller.dart';
import '../application/pickup_session_controller.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery_order.dart';
import '../domain/pickup_session.dart';
import 'pickup_checklist_sheet.dart';

/// Full-screen QR scanner for invoice pickup codes (item 6's "rider scans
/// the first invoice QR code... verifies... shows the checklist...
/// confirms picked... scans the second, third, and fourth").
///
/// Each successful scan calls `verify-scan`, briefly confirms which order
/// matched, then opens [showPickupChecklistSheet] for that order. The
/// scanner pauses while the checklist sheet is open and resumes afterward
/// so the rider can keep scanning the rest of their batch in one
/// continuous flow.
class QrScanScreen extends ConsumerStatefulWidget {
  /// Const constructor.
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  late final AnimationController _scanLineController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  CameraPermissionState? _permission;
  bool _processing = false;
  String? _errorMessage;

  /// Set briefly right after a successful match, before the checklist
  /// sheet opens — gives the rider an unambiguous "you just scanned THIS
  /// order" confirmation at the top of the screen (item 6: avoid
  /// confusion about which order was matched, especially mid-batch).
  String? _matchedOrderNumber;

  /// Raw QR strings already sent to `verify-scan` this session. The QR
  /// carries no order id (see [_decodeQrPayload]), so unlike before, we
  /// can't short-circuit a duplicate scan by looking up an order's local
  /// status before calling the server — we don't know which order a scan
  /// is until the server tells us. This dedupes on the literal scanned
  /// string instead, which still catches the common case (rider points
  /// the scanner at the same slip twice in a row) without a network call;
  /// anything it misses is still caught server-side (ALREADY_VERIFIED).
  final Set<String> _sentThisSession = <String>{};

  /// Zoom scale (0.0–1.0) at the start of the current pinch gesture — the
  /// scale delta reported by [GestureDetector.onScaleUpdate] is relative
  /// to gesture start, not absolute, so this anchors it to the scanner's
  /// actual current zoom. Lets a rider pinch in on a small or distant QR
  /// (e.g. one shown on a screen rather than printed) instead of only
  /// being able to physically walk closer.
  double _gestureStartZoom = 0;

  /// Guards [_onBatchEmptied] so a rebuild doesn't schedule a second pop
  /// on top of one already in flight.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensurePermission());
      unawaited(_maybeResumePendingChecklist());
    });
  }

  /// Recovery path carried over from the removed pickup overview: a
  /// rider who verified a scan but lost the checklist (system
  /// back-gesture, accidental close, app restart between scan and
  /// confirm) would otherwise be a dead end — nothing left to scan
  /// (the token is already VERIFIED server-side) and pickup never
  /// confirmed. Re-fetch the pending checklist from the backend and
  /// reopen the sheet directly.
  Future<void> _maybeResumePendingChecklist() async {
    final ActiveDeliveryController active = ref.read(
      activeDeliveryControllerProvider,
    );
    final PickupSessionController session = ref.read(
      pickupSessionControllerProvider,
    );
    final DeliveryOrder? order = active.current;
    if (order == null) return;
    if (session.statusFor(order.orderId) != PickupScanStatus.verified) return;
    if (session.verificationFor(order.orderId) != null) return;

    try {
      final DeliveryRepository repository = ref.read(
        deliveryRepositoryProvider,
      );
      final PickupVerification verification = await repository
          .getPendingChecklist(order.orderId);
      session.markVerified(order.orderId, verification);
      if (!mounted) return;
      await showPickupChecklistSheet(context, order.orderId, verification);
    } on ApiException catch (e) {
      // Nothing pending server-side either — the rider simply scans
      // again; verify-scan handles token lifecycle authoritatively.
      AppLogger.info(
        LogTopic.delivery,
        'pending-checklist recovery found nothing for ${order.orderId}: '
        '${e.backendCode}',
      );
    }
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    unawaited(_scanner.dispose());
    super.dispose();
  }

  Future<void> _ensurePermission() async {
    final CameraPermissionState state = await ref
        .read(cameraPermissionServiceProvider)
        .ensure();
    if (!mounted) return;
    setState(() => _permission = state);
  }

  /// Centered square scan target, sized relative to the available viewport
  /// (clamped so it stays comfortable on both small phones and tablets).
  /// Shared by [MobileScanner]'s `scanWindow` (which actually restricts
  /// detection to this region — not just a visual frame) and the overlay
  /// painter, so what the rider sees lines up exactly with where scanning
  /// happens.
  Rect _scanWindowFor(Size size) {
    final double dimension = (math.min(size.width, size.height) * 0.68).clamp(
      220.0,
      320.0,
    );
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 24),
      width: dimension,
      height: dimension,
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final String? raw = capture.barcodes
        .map((Barcode b) => b.rawValue)
        .firstWhere(
          (String? v) => v != null && v.isNotEmpty,
          orElse: () => null,
        );
    if (raw == null) return;

    setState(() {
      _processing = true;
      _errorMessage = null;
    });

    try {
      await _handleScannedPayload(raw);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Decodes the compact `version.token.sig` wire format printed on
  /// invoice QR codes (see backend `invoiceGenerator.js#buildQrPayload`).
  /// A dot-delimited string rather than JSON keeps the printed QR small —
  /// neither field can contain '.', so a plain split is safe. There is no
  /// order id in the QR at all: the server resolves which order this is
  /// from the token itself, and returns it in the response.
  Map<String, dynamic>? _decodeQrPayload(String raw) {
    final List<String> parts = raw.split('.');
    if (parts.length != 3) return null;
    final int? version = int.tryParse(parts[0]);
    if (version == null) return null;
    final String token = parts[1];
    final String sig = parts[2];
    if (token.isEmpty || sig.isEmpty) return null;
    return <String, dynamic>{'token': token, 'v': version, 'sig': sig};
  }

  Future<void> _handleScannedPayload(String raw) async {
    final Map<String, dynamic>? payload = _decodeQrPayload(raw);
    if (payload == null) {
      AppLogger.warn(
        LogTopic.delivery,
        'QR payload did not match the expected format',
      );
      unawaited(HapticFeedback.heavyImpact());
      setState(
        () => _errorMessage =
            'Invalid QR code — make sure the whole code is inside the frame and try again.',
      );
      return;
    }

    // Client-side short-circuit for the same slip scanned twice in a row
    // (item 6: no duplicate scans) — see field doc on _sentThisSession for
    // why this can't be keyed by order id anymore. The backend enforces
    // the real guarantee either way (ALREADY_VERIFIED/ALREADY_PICKED_UP).
    if (_sentThisSession.contains(raw)) {
      setState(
        () =>
            _errorMessage = 'Already scanned — open it from your pickup list.',
      );
      return;
    }

    await _scanner.stop();

    final PickupSessionController session = ref.read(
      pickupSessionControllerProvider,
    );

    try {
      _sentThisSession.add(raw);
      final DeliveryRepository repository = ref.read(
        deliveryRepositoryProvider,
      );
      final PickupVerification verification = await repository.verifyScan(
        payload,
      );
      session.markVerified(verification.orderId, verification);
      unawaited(HapticFeedback.mediumImpact());

      if (!mounted) return;
      // Flash which order matched at the top of the screen before the
      // checklist sheet takes over, so there's no ambiguity mid-batch.
      setState(() => _matchedOrderNumber = verification.orderNumber);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      setState(() => _matchedOrderNumber = null);

      final bool? confirmed = await showPickupChecklistSheet(
        context,
        verification.orderId,
        verification,
      );

      if (!mounted) return;
      if (confirmed == true) {
        // Pickup confirmed: pop back to the pickup navigation screen —
        // it rebuilds into the in-transit delivery phase. (The scanner
        // is a pushed screen in the Phase 11 flow; the router's
        // active-delivery gate no longer navigates for us.)
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        return;
      }
      await _scanner.start();
    } on ApiException catch (e) {
      AppLogger.warn(
        LogTopic.delivery,
        'verify-scan rejected: ${e.backendCode}',
        error: e,
      );
      unawaited(HapticFeedback.heavyImpact());
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
      await _scanner.start();
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.delivery,
        'verify-scan failed',
        error: e,
        stackTrace: stack,
      );
      unawaited(HapticFeedback.heavyImpact());
      if (!mounted) return;
      setState(
        () => _errorMessage =
            'Could not verify this code. Check your connection and try again.',
      );
      await _scanner.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final PickupSessionController session = ref.watch(
      pickupSessionControllerProvider,
    );
    final ActiveDeliveryController active = ref.watch(
      activeDeliveryControllerProvider,
    );
    final DeliveryOrder? activeOrder = active.current;
    final bool pickupConfirmed =
        activeOrder != null &&
        session.statusFor(activeOrder.orderId) == PickupScanStatus.pickedUp;
    // Shown before any scan happens (item 6): the QR itself carries no
    // order id, so this is the only place the rider sees which order
    // they're collecting for ahead of time, not just after a match.
    final String pendingOrderNumber = activeOrder != null && !pickupConfirmed
        ? '#${activeOrder.orderNumber}'
        : '';

    // The active order can disappear from underneath the scanner — an
    // admin cancelling or force-delivering it removes it from
    // ActiveDeliveryController live, but nothing else about this
    // full-screen camera UI would otherwise notice: the camera keeps
    // running and the header just goes stale, leaving the rider stuck
    // on a scanner for an order that's already gone. Close it
    // automatically instead of waiting for the rider to manually back
    // out.
    if (activeOrder == null && !_closing && !_processing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('This order is no longer available')),
        );
        context.pop();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size viewport = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final Rect scanWindow = _scanWindowFor(viewport);

            return Stack(
              children: <Widget>[
                if (_permission == CameraPermissionState.granted)
                  GestureDetector(
                    onScaleStart: (_) =>
                        _gestureStartZoom = _scanner.value.zoomScale,
                    onScaleUpdate: (ScaleUpdateDetails details) {
                      final double next =
                          (_gestureStartZoom + (details.scale - 1) * 0.6).clamp(
                            0.0,
                            1.0,
                          );
                      unawaited(_scanner.setZoomScale(next));
                    },
                    child: MobileScanner(
                      controller: _scanner,
                      onDetect: _onDetect,
                      scanWindow: scanWindow,
                      overlayBuilder: (BuildContext context, BoxConstraints _) {
                        return AnimatedBuilder(
                          animation: _scanLineController,
                          builder: (BuildContext context, Widget? child) {
                            return CustomPaint(
                              size: viewport,
                              painter: _ScannerOverlayPainter(
                                scanWindow: scanWindow,
                                scanLineProgress: _scanLineController.value,
                                matched: _matchedOrderNumber != null,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  )
                else
                  const ColoredBox(color: AppColors.black),
                if (_permission == CameraPermissionState.granted &&
                    _matchedOrderNumber == null &&
                    _errorMessage == null)
                  _ScanInstruction(top: scanWindow.bottom + 20),
                _TopBar(onClose: () => context.pop()),
                if (pendingOrderNumber.isNotEmpty &&
                    _matchedOrderNumber == null)
                  _PendingOrdersLabel(orderNumber: pendingOrderNumber),
                if (_matchedOrderNumber != null)
                  _MatchedBanner(orderNumber: _matchedOrderNumber!),
                if (_permission != null &&
                    _permission != CameraPermissionState.granted)
                  _PermissionBlocker(
                    state: _permission!,
                    onOpenSettings: () => ref
                        .read(cameraPermissionServiceProvider)
                        .openAppSettings(),
                    onRetry: _ensurePermission,
                  ),
                if (_errorMessage != null)
                  _ErrorBanner(
                    message: _errorMessage!,
                    onDismiss: () => setState(() => _errorMessage = null),
                  ),
                if (_processing)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.white),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dimmed scrim with a clear cutout over the scan window, white corner
/// brackets, and a soft animated sweep line — the standard "viewfinder"
/// pattern used by UPI/payment-app scanners (Google Pay, PhonePe, etc.),
/// so riders get an immediately familiar, professional scanning UI rather
/// than a bare full-screen camera feed. Turns green briefly on a match.
class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({
    required this.scanWindow,
    required this.scanLineProgress,
    required this.matched,
  });

  final Rect scanWindow;
  final double scanLineProgress;
  final bool matched;

  static const double _cornerRadius = 16;
  static const double _bracketLength = 30;
  static const double _bracketStroke = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect cutout = RRect.fromRectAndRadius(
      scanWindow,
      const Radius.circular(_cornerRadius),
    );

    final Path scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(cutout),
    );
    canvas.drawPath(scrimPath, Paint()..color = const Color(0xB3000000));

    final Color accent = matched ? AppColors.success : AppColors.white;

    canvas.drawRRect(
      cutout,
      Paint()
        ..color = accent.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final Paint bracketPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = _bracketStroke
      ..strokeCap = StrokeCap.round;

    void drawCorner(Offset corner, Offset horizontal, Offset vertical) {
      canvas.drawLine(
        corner,
        corner + horizontal * _bracketLength,
        bracketPaint,
      );
      canvas.drawLine(corner, corner + vertical * _bracketLength, bracketPaint);
    }

    drawCorner(scanWindow.topLeft, const Offset(1, 0), const Offset(0, 1));
    drawCorner(scanWindow.topRight, const Offset(-1, 0), const Offset(0, 1));
    drawCorner(scanWindow.bottomLeft, const Offset(1, 0), const Offset(0, -1));
    drawCorner(
      scanWindow.bottomRight,
      const Offset(-1, 0),
      const Offset(0, -1),
    );

    if (!matched) {
      final double lineY =
          scanWindow.top + scanWindow.height * scanLineProgress;
      final Rect lineRect = Rect.fromLTWH(
        scanWindow.left + 10,
        lineY - 1,
        scanWindow.width - 20,
        2,
      );
      final Paint linePaint = Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(lineRect);
      canvas.drawRect(lineRect, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.scanWindow != scanWindow ||
      oldDelegate.scanLineProgress != scanLineProgress ||
      oldDelegate.matched != matched;
}

class _ScanInstruction extends StatelessWidget {
  const _ScanInstruction({required this.top});

  final double top;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: 24,
      right: 24,
      child: Text(
        'Align the QR code within the frame',
        textAlign: TextAlign.center,
        style: AppTypography.body.copyWith(
          color: AppColors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// Shown at the top before any scan happens — which order(s) this scan
/// session is collecting for, so the rider has that context up front
/// rather than only finding out after a QR is matched.
class _PendingOrdersLabel extends StatelessWidget {
  const _PendingOrdersLabel({required this.orderNumber});

  final String orderNumber;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 64,
      left: 16,
      right: 16,
      child: Text(
        'Scanning for $orderNumber',
        textAlign: TextAlign.center,
        style: AppTypography.label.copyWith(
          color: AppColors.white.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _MatchedBanner extends StatelessWidget {
  const _MatchedBanner({required this.orderNumber});

  final String orderNumber;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 64,
      left: 16,
      right: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.success,
          borderRadius: BorderRadius.circular(12),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.success.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.check_circle, color: AppColors.white, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Order #$orderNumber matched',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(color: AppColors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.close, color: AppColors.white),
              onPressed: onClose,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              const Icon(Icons.error_outline, color: AppColors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: AppTypography.body.copyWith(color: AppColors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.white, size: 18),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionBlocker extends StatelessWidget {
  const _PermissionBlocker({
    required this.state,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final CameraPermissionState state;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final bool permanentlyDenied =
        state == CameraPermissionState.deniedForever ||
        state == CameraPermissionState.restricted;

    return ColoredBox(
      color: AppColors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.camera_alt_outlined,
                size: 48,
                color: AppColors.white,
              ),
              const SizedBox(height: 16),
              Text(
                'Camera access needed',
                textAlign: TextAlign.center,
                style: AppTypography.heading.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: 8),
              Text(
                permanentlyDenied
                    ? 'Enable camera access in Settings to scan pickup QR codes.'
                    : 'We need your camera to scan invoice QR codes at pickup.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  color: AppColors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: permanentlyDenied ? 'Open Settings' : 'Allow Camera',
                onPressed: permanentlyDenied ? onOpenSettings : () => onRetry(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
