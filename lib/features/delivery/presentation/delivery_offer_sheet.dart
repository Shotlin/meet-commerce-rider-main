import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/maps/geo.dart';
import '../../../core/maps/geo_point.dart';
import '../../../core/providers.dart';
import '../../../core/location/rider_location_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_haptics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/action_failure_watcher.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/diagnostic_expander.dart';
import '../application/offers_controller.dart';
import '../data/delivery_api.dart' show RejectReason;
import '../domain/delivery_order.dart';
import 'reject_reason_sheet.dart';

/// Outcome of [showDeliveryOfferSheet].
enum OfferSheetOutcome {
  /// Rider tapped Accept and the network call succeeded.
  accepted,

  /// Rider tapped Decline and chose a reason; the reject call has been
  /// dispatched.
  declined,

  /// Rider dismissed the sheet without acting (or accept/decline failed
  /// in a way that should leave the offer in the list).
  dismissed,
}

/// Result returned from [showDeliveryOfferSheet].
@immutable
class OfferSheetResult {
  /// Constructs a result explicitly.
  const OfferSheetResult(this.outcome, {this.message});

  /// Convenience: dismissed without action.
  const OfferSheetResult.dismissed()
    : outcome = OfferSheetOutcome.dismissed,
      message = null;

  /// What the rider did.
  final OfferSheetOutcome outcome;

  /// Optional user-facing message (e.g. "Order was already taken").
  final String? message;
}

/// Copy used for the lost-race outcome (§9 item 7 / design §10: a short
/// "taken by another rider" feedback, then a clean return to waiting).
const String kOfferTakenMessage = 'Order taken by another rider';

/// Presents the new-offer bottom sheet for [order] (design §10).
///
/// Layout (top to bottom):
/// - 4 dp drag handle.
/// - `New delivery` label + order number, big earning amount.
/// - Vertical route timeline: Rider → FreshCuts Store (with the live
///   rider-to-pickup distance when a GPS fix and store coordinates
///   exist) → Customer area (locality only — full customer details
///   arrive after acceptance, requirement §8).
/// - Metric chips: total distance, ETA, item count, payment mode.
/// - **Sticky** bottom action row: `Decline` (secondary, narrower) and
///   `Accept order` (primary red, wider) — §10 "Accept should occupy
///   more width than Decline".
///
/// Race safety (requirement §9): the rider never sees an optimistic
/// assignment — the accept button shows progress until the backend
/// answers. If the offer is lost in realtime (`order:expired` /
/// taken-by-another-rider removes it from [OffersController]) while no
/// action is in flight, the sheet closes itself and the caller surfaces
/// [kOfferTakenMessage].
///
/// No countdown is rendered: the backend currently enforces no offer
/// expiry (`offerTimeoutSeconds: 0`), and requirement §8 forbids a fake
/// timer.
///
/// Returns an [OfferSheetResult] describing what the rider did.
Future<OfferSheetResult> showDeliveryOfferSheet(
  BuildContext context,
  DeliveryOrder order,
) async {
  // Fixed-height sheet (no drag-to-resize): the offer body scrolls
  // internally via its own SingleChildScrollView, so a draggable snap
  // range isn't needed. A fast drag against the snap-animated
  // DraggableScrollableSheet here was observed to corrupt the element
  // tree (Flutter framework assertion in _InactiveElements._unmount),
  // the same class of issue the active-delivery screen avoided by
  // dropping its DraggableScrollableSheet for a fixed panel.
  final OfferSheetResult? result = await showAppBottomSheet<OfferSheetResult>(
    context,
    initialChildSize: 0.6,
    snapSizes: const <double>[0.6],
    enableDrag: false,
    builder: (BuildContext sheetContext) =>
        _DeliveryOfferSheetBody(order: order),
  );
  return result ?? const OfferSheetResult.dismissed();
}

class _DeliveryOfferSheetBody extends ConsumerStatefulWidget {
  const _DeliveryOfferSheetBody({required this.order});

  final DeliveryOrder order;

  @override
  ConsumerState<_DeliveryOfferSheetBody> createState() =>
      _DeliveryOfferSheetBodyState();
}

class _DeliveryOfferSheetBodyState
    extends ConsumerState<_DeliveryOfferSheetBody> {
  /// Tracks consecutive accept failures for R27.5.
  final ActionFailureWatcher _failureWatcher = ActionFailureWatcher();

  /// Whether to render the diagnostic expander below the CTA.
  bool _showDiagnostic = false;

  /// Rows shown inside the diagnostic expander (updated on each failure).
  List<MapEntry<String, String>> _diagnosticRows =
      const <MapEntry<String, String>>[];

  /// Set once accept/decline has settled. After that the realtime
  /// removal of the offer is this sheet's OWN doing (the controller
  /// removes an accepted/rejected offer) and must not trigger the
  /// lost-race auto-close.
  bool _decisionSettled = false;

  /// Whether a network decision is currently awaited. The controller
  /// notifies listeners both mid-action (busy set) and after the
  /// finally block clears the busy flag — the latter lands *before*
  /// control returns to this class, so the listener must also skip
  /// while this flag is up or it would auto-close a sheet whose
  /// outcome is about to be handled.
  bool _actionInFlight = false;

  @override
  Widget build(BuildContext context) {
    // Realtime loss (§9 item 7): the offer vanished from the controller
    // while this sheet was open and no action was in flight — another
    // rider won or ops removed it. Close cleanly with the loss result;
    // the caller shows the feedback.
    ref.listen<OffersController>(offersControllerProvider, (
      OffersController? previous,
      OffersController next,
    ) {
      if (_decisionSettled || _actionInFlight || !mounted) return;
      if (next.isBusy(widget.order.orderId)) return;
      final bool stillOffered = next.offers.any(
        (DeliveryOrder o) => o.orderId == widget.order.orderId,
      );
      if (stillOffered) return;
      _decisionSettled = true;
      Navigator.of(context).pop<OfferSheetResult>(
        const OfferSheetResult(
          OfferSheetOutcome.dismissed,
          message: kOfferTakenMessage,
        ),
      );
    });

    final OffersController controller = ref.watch<OffersController>(
      offersControllerProvider,
    );
    final bool busy = controller.isBusy(widget.order.orderId);
    final ScrollController? primary = PrimaryScrollController.maybeOf(context);
    final bool commissionEnabled =
        ref.watch(riderProfileProvider).asData?.value.commissionEnabled ?? true;
    final GeoPoint? riderPosition = ref
        .watch(riderLocationNotifierProvider)
        .value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SheetHandle(),
        Flexible(
          child: SingleChildScrollView(
            controller: primary,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'New delivery',
                            style: AppTypography.micro.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '#${widget.order.orderNumber}',
                            style: AppTypography.label.copyWith(
                              color: AppColors.charcoal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (commissionEnabled) ...<Widget>[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            '₹${widget.order.riderEarning.toStringAsFixed(0)}',
                            style: AppTypography.display.copyWith(
                              color: AppColors.brand,
                            ),
                          ),
                          Text(
                            'Your earning',
                            style: AppTypography.micro.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppDimensions.lg),

                // Route timeline (design §10): Rider → Store → Customer
                // area.
                _OfferTimeline(
                  order: widget.order,
                  riderPosition: riderPosition,
                ),
                const SizedBox(height: AppDimensions.lg),

                // Metric chips: total trip distance, ETA, items, payment.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (widget.order.estimatedDistance != null)
                      _MetricChip(
                        icon: Icons.route_outlined,
                        label:
                            '${widget.order.estimatedDistance!.toStringAsFixed(1)} km trip',
                      ),
                    _MetricChip(
                      icon: Icons.timer_outlined,
                      label: '${widget.order.estimatedDuration} min',
                    ),
                    _MetricChip(
                      icon: Icons.shopping_bag_outlined,
                      label:
                          '${widget.order.items.length} item${widget.order.items.length == 1 ? '' : 's'}',
                    ),
                    _MetricChip(
                      icon: widget.order.paymentMethod.toUpperCase() == 'COD'
                          ? Icons.payments_outlined
                          : Icons.credit_card_outlined,
                      label: widget.order.paymentMethod.toUpperCase() == 'COD'
                          ? 'Cash on delivery'
                          : 'Prepaid',
                    ),
                  ],
                ),

                // R27.5: show diagnostic expander after 2+ failures within 10s.
                if (_showDiagnostic) ...<Widget>[
                  const SizedBox(height: AppDimensions.md),
                  DiagnosticExpander(
                    summary: 'Show error details',
                    rows: _diagnosticRows,
                  ),
                ],
              ],
            ),
          ),
        ),

        // Sticky two-button action region (design §10): Decline left
        // (secondary), Accept order right (primary red, wider). Always
        // on screen — the decision must never scroll out of reach.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: AppButton(
                  label: 'Decline',
                  variant: AppButtonVariant.secondary,
                  onPressed: busy ? null : () => _onDecline(context),
                ),
              ),
              const SizedBox(width: AppDimensions.md),
              Expanded(
                flex: 3,
                child: AppButton(
                  label: 'Accept order',
                  isLoading: busy,
                  onPressed: busy ? null : () => _onAccept(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onAccept(BuildContext context) async {
    final OffersController controller = ref.read<OffersController>(
      offersControllerProvider,
    );
    final NavigatorState navigator = Navigator.of(context);
    _actionInFlight = true;
    final OfferActionResult result = await controller.acceptOffer(
      widget.order.orderId,
    );
    if (!navigator.mounted) return;
    switch (result) {
      case OfferActionSuccess():
        // Reset failure counter on success.
        _failureWatcher.reset(widget.order.orderId);
        _decisionSettled = true;
        _actionInFlight = false;
        unawaited(Future<void>.sync(AppHaptics.accept));
        navigator.pop<OfferSheetResult>(
          const OfferSheetResult(OfferSheetOutcome.accepted),
        );
      case OfferAlreadyTaken(message: final String message):
        _decisionSettled = true;
        _actionInFlight = false;
        unawaited(Future<void>.sync(AppHaptics.warning));
        navigator.pop<OfferSheetResult>(
          OfferSheetResult(OfferSheetOutcome.dismissed, message: message),
        );
      case OfferActionFailure(message: final String message):
        _actionInFlight = false;
        unawaited(Future<void>.sync(AppHaptics.warning));
        _failureWatcher.record(widget.order.orderId, message);
        final bool showDiag = _failureWatcher.shouldShowDiagnostic(
          widget.order.orderId,
        );
        setState(() {
          _showDiagnostic = showDiag;
          _diagnosticRows = _failureWatcher.diagnosticRows(
            widget.order.orderId,
          );
        });
        ScaffoldMessenger.maybeOf(
          navigator.context,
        )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _onDecline(BuildContext context) async {
    final RejectReason? reason = await showRejectReasonSheet(context);
    if (reason == null) return;
    if (!context.mounted) return;
    final OffersController controller = ref.read<OffersController>(
      offersControllerProvider,
    );
    final NavigatorState navigator = Navigator.of(context);
    _actionInFlight = true;
    final OfferActionResult result = await controller.rejectOffer(
      widget.order.orderId,
      reason,
    );
    if (!navigator.mounted) return;
    switch (result) {
      case OfferActionSuccess():
        _decisionSettled = true;
        _actionInFlight = false;
        navigator.pop<OfferSheetResult>(
          const OfferSheetResult(
            OfferSheetOutcome.declined,
            message: 'Order declined',
          ),
        );
      case OfferAlreadyTaken(message: final String message):
        _decisionSettled = true;
        _actionInFlight = false;
        unawaited(Future<void>.sync(AppHaptics.warning));
        navigator.pop<OfferSheetResult>(
          OfferSheetResult(OfferSheetOutcome.dismissed, message: message),
        );
      case OfferActionFailure(message: final String message):
        ScaffoldMessenger.maybeOf(
          navigator.context,
        )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// Standardised 4 dp top handle used inside the offer sheet. Mirrors
/// the handle drawn by [AppSheetScaffold] but inlined here so the
/// sheet can place it above a [Flexible] scroll region without
/// fighting the column's min-size constraint.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: SizedBox(
          width: 40,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical route timeline (design §10): `Rider → FreshCuts Store →
/// Customer area`, with the live rider-to-pickup distance on the store
/// node when a GPS fix and store coordinates exist, and — deliberately —
/// no customer name pre-accept (requirement §8: destination
/// locality/area only).
class _OfferTimeline extends StatelessWidget {
  const _OfferTimeline({required this.order, required this.riderPosition});

  final DeliveryOrder order;
  final GeoPoint? riderPosition;

  @override
  Widget build(BuildContext context) {
    final String? pickupDistance = _pickupDistanceLabel();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        children: <Widget>[
          const _TimelineNode(
            icon: Icons.my_location,
            title: 'Your location',
            subtitle: null,
            isFirst: true,
          ),
          const _TimelineConnector(),
          _TimelineNode(
            icon: Icons.storefront_outlined,
            title: order.storeAddress.name,
            subtitle: pickupDistance == null
                ? order.storeAddress.address
                : '$pickupDistance · ${order.storeAddress.address}',
            highlight: true,
          ),
          const _TimelineConnector(),
          _TimelineNode(
            icon: Icons.location_on_outlined,
            title:
                order.customerAddress.landmark ?? order.customerAddress.address,
            subtitle: order.customerAddress.landmark == null
                ? null
                : order.customerAddress.address,
          ),
        ],
      ),
    );
  }

  /// Rider-to-pickup distance from the live GPS fix and the store's
  /// coordinates. `null` when either is missing — no fabricated value.
  String? _pickupDistanceLabel() {
    final GeoPoint? rider = riderPosition;
    final double? storeLat = order.storeAddress.lat;
    final double? storeLng = order.storeAddress.lng;
    if (rider == null || storeLat == null || storeLng == null) return null;
    final double meters = Geo.distanceMeters(
      rider,
      GeoPoint(storeLat, storeLng),
    );
    if (meters < 1000) return '${meters.round()} m to pickup';
    return '${(meters / 1000).toStringAsFixed(1)} km to pickup';
  }
}

/// One row of the route timeline.
class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isFirst = false,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isFirst;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: highlight ? AppColors.brand : AppColors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: highlight ? AppColors.brand : AppColors.border,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: highlight ? AppColors.white : AppColors.muted,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!isFirst)
                Text(
                  title,
                  style: AppTypography.label.copyWith(
                    color: AppColors.charcoal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (!isFirst && subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (isFirst)
                Text(
                  title,
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineConnector extends StatelessWidget {
  const _TimelineConnector();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 14),
      child: SizedBox(
        height: 14,
        width: 2,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.brandBorder),
        ),
      ),
    );
  }
}

/// Standardised metric chip inside the offer sheet.
class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: AppColors.charcoal),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.label.copyWith(color: AppColors.charcoal),
          ),
        ],
      ),
    );
  }
}
