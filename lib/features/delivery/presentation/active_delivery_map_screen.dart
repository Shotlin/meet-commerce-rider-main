import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as ul;

import '../../../app/router.dart';
import '../../../core/location/delivery_location_phase_sync.dart';
import '../../../core/location/location_lifecycle_manager.dart';
import '../../../core/location/rider_location_provider.dart';
import '../../../core/maps/geo.dart';
import '../../../core/maps/rider_map.dart';
import '../../../core/maps/geo_point.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/external_nav_launcher.dart';
import '../../../shared/widgets/app_button.dart';
import '../application/active_delivery_controller.dart';
import '../application/active_delivery_map_controller.dart';
import '../application/delivery_socket_controller.dart';
import '../domain/assignment_status.dart';
import '../domain/delivery_address.dart';
import '../domain/delivery_order.dart';
import '../domain/store_info.dart';
import 'in_transit_sheet.dart' show AddressCard, InTransitSheet;
import 'completion_summary_sheet.dart';

/// Map-first screen the rider sees while completing an active
/// delivery (R12).
///
/// Three layers (top-down):
///
/// 1. A long-lived [RiderMap] rendering Ola's vector style through
///    MapLibre native (Big Phase 12). Marker / route updates flow
///    through [ActiveDeliveryMapController] (a [ChangeNotifier])
///    consumed via a [ValueListenableBuilder] reading the rider's
///    [ValueNotifier<GeoPoint?>] from [riderLocationNotifierProvider]
///    so the surrounding [Scaffold] never rebuilds when the rider
///    moves (R25.1).
/// 2. A status pill in the top SafeArea reflecting the
///    [AssignmentStatus] phase ("Heading to store" / "Heading to
///    customer" / "Delivered").
/// 3. A [DraggableScrollableSheet] anchored at the bottom with
///    snap positions `[0.20, 0.48, 0.82]` carrying the
///    phase-specific actions (call, navigate, mark picked up /
///    deliver). A floating recenter button sits above the sheet,
///    visible only while the rider is mid-pan.
class ActiveDeliveryMapScreen extends ConsumerStatefulWidget {
  const ActiveDeliveryMapScreen({super.key});

  @override
  ConsumerState<ActiveDeliveryMapScreen> createState() =>
      _ActiveDeliveryMapScreenState();
}

class _ActiveDeliveryMapScreenState
    extends ConsumerState<ActiveDeliveryMapScreen> {
  /// Imperative camera handle from [RiderMap] (recenter).
  RiderMapHandle? _mapHandle;

  /// Drives the state-aware GPS location profile (§23) from the
  /// delivery phase: waiting → accepted → in-transit → waiting.
  final DeliveryLocationPhaseSync _locationPhaseSync =
      DeliveryLocationPhaseSync();

  ValueNotifier<GeoPoint?>? _riderNotifier;
  void Function()? _riderListener;

  String? _appliedOrderId;
  AssignmentStatus? _appliedStatus;

  String? _summaryShownForOrderId;
  bool _summaryVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_warmMarkers());
      unawaited(_startLocationStream());
    });
  }

  Future<void> _startLocationStream() async {
    if (!mounted) return;
    final LocationLifecycleManager manager = ref.read<LocationLifecycleManager>(
      locationLifecycleManagerProvider,
    );
    // Ensure the stream is running — the manager handles permission,
    // seeding, and backend uploads automatically.
    if (!manager.isStreaming) {
      await manager.onWentOnline();
    }
  }

  Future<void> _warmMarkers() async {
    if (!mounted) return;
    final DeliveryOrder? order = ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider)
        .current;
    if (order != null) {
      unawaited(_applyOrderToMap(order));
    }
    _bindRiderNotifier();
  }

  void _bindRiderNotifier() {
    final ValueNotifier<GeoPoint?> notifier = ref
        .read<ValueNotifier<GeoPoint?>>(riderLocationNotifierProvider);
    if (identical(_riderNotifier, notifier)) return;
    _detachRiderNotifier();
    _riderNotifier = notifier;
    _riderListener = _onRiderPositionChanged;
    notifier.addListener(_riderListener!);
    final GeoPoint? seed = notifier.value;
    if (seed != null) {
      ref
          .read<ActiveDeliveryMapController>(
            activeDeliveryMapControllerProvider,
          )
          .updateRiderPosition(seed);
    }
  }

  void _detachRiderNotifier() {
    final ValueNotifier<GeoPoint?>? n = _riderNotifier;
    final void Function()? l = _riderListener;
    if (n != null && l != null) {
      n.removeListener(l);
    }
    _riderNotifier = null;
    _riderListener = null;
  }

  void _onRiderPositionChanged() {
    if (!mounted) return;
    final GeoPoint? next = _riderNotifier?.value;
    if (next == null) return;
    final ActiveDeliveryMapController map = ref
        .read<ActiveDeliveryMapController>(activeDeliveryMapControllerProvider);
    map.updateRiderPosition(next);
  }

  Future<void> _applyOrderToMap(DeliveryOrder order) async {
    final ActiveDeliveryMapController map = ref
        .read<ActiveDeliveryMapController>(activeDeliveryMapControllerProvider);
    final StoreInfo? store = ref
        .read<AsyncValue<StoreInfo>>(storeInfoProvider)
        .value;
    map.applyOrder(order, store);

    // Requirement §23: tracking frequency follows the delivery phase.
    // Fire-and-forget — the sync is idempotent and the manager
    // early-returns on unchanged profiles.
    await _locationPhaseSync.apply(
      map.phase,
      ref.read<LocationLifecycleManager>(locationLifecycleManagerProvider),
    );
  }

  @override
  void dispose() {
    _detachRiderNotifier();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Camera autopilot
  // ---------------------------------------------------------------------------

  void _onUserPan() {
    ref
        .read<ActiveDeliveryMapController>(activeDeliveryMapControllerProvider)
        .setShowRecenterButton(true);
  }

  void _onRecenterPressed() {
    _mapHandle?.recenter();
    ref
        .read<ActiveDeliveryMapController>(activeDeliveryMapControllerProvider)
        .setShowRecenterButton(false);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ActiveDeliveryController activeDelivery = ref
        .watch<ActiveDeliveryController>(activeDeliveryControllerProvider);
    final DeliveryOrder? order = activeDelivery.current;

    if (order == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(AppRoutes.home);
      });
      return const _ActiveDeliveryGoneScreen();
    }

    if (order.orderId != _appliedOrderId ||
        order.assignmentStatus != _appliedStatus) {
      _appliedOrderId = order.orderId;
      _appliedStatus = order.assignmentStatus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_applyOrderToMap(order));
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeShowCompletionSummary(order);
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        context.go(AppRoutes.home);
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: Column(
          children: <Widget>[
            // Map + overlay controls fill all available space above the panel.
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _MapLayer(
                      order: order,
                      onReady: (RiderMapHandle handle) => _mapHandle = handle,
                      onUserPan: _onUserPan,
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.viewPaddingOf(context).top + 12,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _NavTopBar(
                          status: order.assignmentStatus,
                          order: order,
                        ),
                      ],
                    ),
                  ),
                  // Floating recenter button — bottom-right, clear of panel.
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: _RecenterButton(onPressed: _onRecenterPressed),
                  ),
                ],
              ),
            ),
            // Fixed step-action panel anchored to the bottom.
            _StepActionPanel(order: order),
          ],
        ),
      ),
    );
  }

  void _maybeShowCompletionSummary(DeliveryOrder order) {
    if (_summaryVisible) return;
    if (order.assignmentStatus != AssignmentStatus.delivered) return;
    if (_summaryShownForOrderId == order.orderId) return;
    _summaryShownForOrderId = order.orderId;
    _summaryVisible = true;
    final BuildContext rootContext = context;
    final double totalToday =
        ref
            .read(homeDashboardControllerProvider)
            .earningsToday
            ?.totalEarnings ??
        order.riderEarning;
    unawaited(
      showCompletionSummarySheet(
        rootContext,
        orderId: order.orderId,
        earnedAmount: order.riderEarning,
        customerName: order.customerAddress.name.isNotEmpty
            ? order.customerAddress.name
            : order.customerAddress.address,
        orderNumber: order.orderNumber,
        totalEarningsToday: totalToday,
      ).whenComplete(() {
        _summaryVisible = false;
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Map layer
// ---------------------------------------------------------------------------

class _MapLayer extends ConsumerWidget {
  const _MapLayer({
    required this.order,
    required this.onReady,
    required this.onUserPan,
  });

  final DeliveryOrder order;
  final ValueChanged<RiderMapHandle> onReady;
  final VoidCallback onUserPan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ActiveDeliveryMapController map = ref
        .watch<ActiveDeliveryMapController>(
          activeDeliveryMapControllerProvider,
        );
    final ValueNotifier<GeoPoint?> rider = ref.read<ValueNotifier<GeoPoint?>>(
      riderLocationNotifierProvider,
    );

    return ValueListenableBuilder<GeoPoint?>(
      valueListenable: rider,
      builder: (BuildContext context, GeoPoint? riderPos, _) {
        // Keep the controller's rider marker/camera state in sync with
        // the notifier (the surrounding screen never rebuilds on GPS
        // ticks — R25.1).
        ref
            .read<ActiveDeliveryMapController>(
              activeDeliveryMapControllerProvider,
            )
            .updateRiderPosition(
              riderPos ?? map.riderPosition ?? _defaultTarget,
            );
        return RiderMap(
          availability: ref.watch(olaMapsAvailabilityProvider.future),
          markers: map.markers,
          route: map.route,
          followTarget: riderPos ?? map.riderPosition,
          fitPoints: map.fitPoints,
          pitched: false,
          initialZoom: 14,
          onUserPan: onUserPan,
          onReady: onReady,
          fallbackBuilder: (BuildContext context) =>
              const _MapUnavailablePanel(),
        );
      },
    );
  }
}

/// Shown when Ola Maps isn't configured dashboard-side — an honest
/// surface, not a blank canvas (no-placeholder rule).
class _MapUnavailablePanel extends StatelessWidget {
  const _MapUnavailablePanel();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFEAECEF),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.map_outlined, size: 40, color: Color(0xFF667085)),
              SizedBox(height: 12),
              Text(
                'Map unavailable',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101114),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Ola Maps is not configured for this environment yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const GeoPoint _defaultTarget = GeoPoint(12.9716, 77.5946);

// ---------------------------------------------------------------------------
// Top navigation bar (status + ETA card)
// ---------------------------------------------------------------------------

/// Combined top bar: phase status pill on the left, road-snapped
/// ETA / distance card on the right. Glass-morphism look:
/// translucent white surface, soft shadow, rounded corners.
class _NavTopBar extends ConsumerWidget {
  const _NavTopBar({required this.status, required this.order});

  final AssignmentStatus status;
  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ActiveDeliveryMapController map = ref
        .watch<ActiveDeliveryMapController>(
          activeDeliveryMapControllerProvider,
        );

    final (String label, Color dotColor) = switch (status) {
      AssignmentStatus.assigned => ('New offer', AppColors.warning),
      AssignmentStatus.accepted => ('Heading to pickup', AppColors.mapBlue),
      AssignmentStatus.inTransit => ('Heading to customer', AppColors.success),
      AssignmentStatus.delivered => ('Delivered', AppColors.success),
      AssignmentStatus.cancelled => ('Cancelled', AppColors.danger),
    };

    // §11 top card: the FreshCuts store the rider is heading to (only
    // in the pickup phase — in transit belongs to the customer).
    final String? headline = status == AssignmentStatus.accepted
        ? order.storeAddress.name
        : null;

    final double? meters = map.distanceMeters;
    final int? etaMin = map.etaMinutes;
    final String distanceLabel;
    if (meters == null) {
      distanceLabel = '—';
    } else if (meters < 1000) {
      distanceLabel = '${meters.round()} m';
    } else {
      distanceLabel = '${(meters / 1000).toStringAsFixed(1)} km';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: _GlassCard(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.label.copyWith(
                          color: AppColors.charcoal,
                        ),
                      ),
                      if (headline != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          headline,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.micro.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (status == AssignmentStatus.accepted &&
            (order.storeAddress.phone?.isNotEmpty ?? false))
          _GlassCard(
            child: _NavTopBarCallButton(phone: order.storeAddress.phone!),
          ),
        if (meters != null && etaMin != null)
          _GlassCard(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.directions_outlined,
                  size: 16,
                  color: AppColors.mapBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  '$distanceLabel · ${etaMin}m',
                  style: AppTypography.label.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 8),
        _RefreshButton(
          onPressed: () => ref
              .read<DeliverySocketController>(deliverySocketControllerProvider)
              .refreshOrders(),
        ),
      ],
    );
  }
}

/// Compact call action for the §11 top floating card.
class _NavTopBarCallButton extends ConsumerWidget {
  const _NavTopBarCallButton({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () async {
        final UrlLauncherDelegate launcher = ref.read<UrlLauncherDelegate>(
          urlLauncherDelegateProvider,
        );
        final Uri uri = Uri(scheme: 'tel', path: phone);
        if (await launcher.canLaunch(uri)) {
          await launcher.launch(uri, mode: ul.LaunchMode.externalApplication);
        }
      },
      customBorder: const CircleBorder(),
      child: const Icon(
        Icons.call_outlined,
        size: 18,
        color: AppColors.mapBlue,
      ),
    );
  }
}

/// Manually re-syncs the batch against the server — a rider-visible
/// escape hatch for when an admin-side change (cancellation, status
/// update) hasn't yet reached this device live, so the order doesn't
/// stay stuck until the rider force-closes and reopens the app.
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: const _GlassCard(
        child: Icon(Icons.refresh, size: 18, color: AppColors.charcoal),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RecenterButton extends ConsumerWidget {
  const _RecenterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.white,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.my_location, color: AppColors.black, size: 22),
        ),
      ),
    );
  }
}

class _ActiveDeliveryGoneScreen extends StatelessWidget {
  const _ActiveDeliveryGoneScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.white,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No active delivery',
            style: AppTypography.body,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixed step-action panel (replaces DraggableScrollableSheet)
// ---------------------------------------------------------------------------

/// A fixed panel anchored to the bottom of the screen that shows the
/// current delivery step and the primary CTA for that step.
///
/// Layout (top → bottom inside the panel):
///   • Step progress bar — pill showing ACCEPTED → IN_TRANSIT → DELIVERED
///   • Order header  — order number + rider earning
///   • Phase body    — address card + action buttons for the current step
///   • Bottom safe-area inset
class _StepActionPanel extends StatelessWidget {
  const _StepActionPanel({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 12),
          _StepProgressBar(status: order.assignmentStatus),
          _PanelHeader(order: order),
          _PhaseBody(order: order),
          SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 16),
        ],
      ),
    );
  }
}

/// Three-step progress pill: Pickup → Deliver → Done.
class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({required this.status});

  final AssignmentStatus status;

  @override
  Widget build(BuildContext context) {
    final bool pickupDone =
        status == AssignmentStatus.inTransit ||
        status == AssignmentStatus.delivered;
    final bool deliverDone = status == AssignmentStatus.delivered;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: <Widget>[
          _StepDot(active: true, done: pickupDone, label: 'Pickup'),
          Expanded(child: _StepLine(active: pickupDone)),
          _StepDot(active: pickupDone, done: deliverDone, label: 'Deliver'),
          Expanded(child: _StepLine(active: deliverDone)),
          _StepDot(active: deliverDone, done: deliverDone, label: 'Done'),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.active,
    required this.done,
    required this.label,
  });

  final bool active;
  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color dotColor = done
        ? AppColors.success
        : active
        ? AppColors.black
        : AppColors.border;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check, size: 12, color: AppColors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTypography.micro.copyWith(
            color: active ? AppColors.charcoal : AppColors.muted,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 16),
      color: active ? AppColors.success : AppColors.border,
    );
  }
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool commissionEnabled =
        ref.watch(riderProfileProvider).asData?.value.commissionEnabled ?? true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '#${order.orderNumber}',
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  commissionEnabled
                      ? '₹${order.riderEarning.toStringAsFixed(0)}'
                      : 'In progress',
                  style: AppTypography.title.copyWith(color: AppColors.black),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.charcoal),
            tooltip: 'Back to home',
            onPressed: () => context.go(AppRoutes.home),
          ),
        ],
      ),
    );
  }
}

class _ApproximateLocationBanner extends StatelessWidget {
  const _ApproximateLocationBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Customer location unavailable - cannot navigate',
              style: AppTypography.body.copyWith(color: AppColors.charcoal),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseBody extends ConsumerWidget {
  const _PhaseBody({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool customerApprox = ref
        .watch<ActiveDeliveryMapController>(activeDeliveryMapControllerProvider)
        .customerLocationApproximate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (order.assignmentStatus == AssignmentStatus.inTransit &&
              customerApprox)
            const _ApproximateLocationBanner(),
          switch (order.assignmentStatus) {
            AssignmentStatus.assigned ||
            AssignmentStatus.accepted => _AcceptedSheet(order: order),
            AssignmentStatus.inTransit => InTransitSheet(order: order),
            AssignmentStatus.delivered => _DeliveredSheet(order: order),
            AssignmentStatus.cancelled => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

/// §11 arrival rule: a real GPS fix within [radiusMeters] of the
/// store's own coordinates reads as "arrived at the store". Returns
/// `false` when either the fix or the store coordinates are missing —
/// no arrival is ever fabricated. Exposed for tests.
@visibleForTesting
bool isRiderArrivedAtStore({
  required GeoPoint? riderPosition,
  required DeliveryOrder order,
  double radiusMeters = 100,
}) {
  final double? lat = order.storeAddress.lat;
  final double? lng = order.storeAddress.lng;
  if (riderPosition == null || lat == null || lng == null) return false;
  final double meters = Geo.distanceMeters(riderPosition, GeoPoint(lat, lng));
  return meters <= radiusMeters;
}

/// The pickup-navigation bottom sheet (design §11 bottom sheet + §12):
/// store address, order number, bag/item count, arrival state, `Start
/// Navigation`, and — as the ONLY way to confirm pickup — the
/// `Scan pickup code` CTA into the verified scan → checklist flow.
/// The seed's self-attested "mark as picked up" bypass was removed in
/// Phase 11: the backend's `order_pickup_tokens` lifecycle is the real
/// store flow.
class _AcceptedSheet extends ConsumerWidget {
  const _AcceptedSheet({required this.order});

  final DeliveryOrder order;

  static const double _arrivalRadiusMeters = 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeliveryAddress addr = order.storeAddress;
    final GeoPoint? riderPosition = ref
        .watch(riderLocationNotifierProvider)
        .value;
    final bool arrived = isRiderArrivedAtStore(
      riderPosition: riderPosition,
      order: order,
      radiusMeters: _arrivalRadiusMeters,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AddressCard(tag: 'Pickup', title: addr.name, subtitle: addr.address),
          const SizedBox(height: 8),
          Text(
            'Order #${order.orderNumber}'
            ' · ${order.items.length} item${order.items.length == 1 ? '' : 's'}',
            style: AppTypography.micro.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (arrived) ...<Widget>[
            const _ArrivedStrip(),
            const SizedBox(height: 12),
          ],
          Row(
            children: <Widget>[
              if (addr.phone != null && addr.phone!.isNotEmpty) ...<Widget>[
                Expanded(
                  child: AppButton(
                    label: 'Call store',
                    variant: AppButtonVariant.secondary,
                    leadingIcon: Icons.call_outlined,
                    onPressed: () => _onCall(ref, addr.phone!),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: AppButton(
                  label: 'Navigate',
                  variant: AppButtonVariant.secondary,
                  leadingIcon: Icons.navigation_outlined,
                  onPressed: addr.lat != null && addr.lng != null
                      ? () => _onNavigate(ref, addr.lat!, addr.lng!)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppButton(
            label: arrived
                ? "You're here — scan pickup code"
                : 'Scan pickup code',
            onPressed: () => unawaited(context.push(AppRoutes.qrScan)),
          ),
        ],
      ),
    );
  }

  Future<void> _onNavigate(WidgetRef ref, double lat, double lng) async {
    final ExternalNavigationLauncher launcher = ref
        .read<ExternalNavigationLauncher>(externalNavLauncherProvider);
    await launcher.openDrivingDirections(destLat: lat, destLng: lng);
  }

  Future<void> _onCall(WidgetRef ref, String phone) async {
    final UrlLauncherDelegate launcher = ref.read<UrlLauncherDelegate>(
      urlLauncherDelegateProvider,
    );
    final Uri uri = Uri(scheme: 'tel', path: phone);
    if (await launcher.canLaunch(uri)) {
      await launcher.launch(uri, mode: ul.LaunchMode.externalApplication);
    }
  }
}

/// §11 arrival state — a calm success strip, not an alarm.
class _ArrivedStrip extends StatelessWidget {
  const _ArrivedStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.location_on_outlined,
            size: 18,
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "You've arrived at the store. Scan the pickup code to continue.",
              style: AppTypography.micro.copyWith(color: AppColors.charcoal),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveredSheet extends ConsumerWidget {
  const _DeliveredSheet({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool commissionEnabled =
        ref.watch(riderProfileProvider).asData?.value.commissionEnabled ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Delivered',
                  style: AppTypography.heading.copyWith(color: AppColors.black),
                ),
                if (commissionEnabled) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'You earned',
                    style: AppTypography.micro.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${order.riderEarning.toStringAsFixed(0)}',
                    style: AppTypography.display.copyWith(
                      color: AppColors.black,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Back to home',
            onPressed: () {
              context.go(AppRoutes.home);
            },
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodPill extends StatelessWidget {
  const _PaymentMethodPill({required this.paymentMethod});

  final String paymentMethod;

  @override
  Widget build(BuildContext context) {
    final String upper = paymentMethod.toUpperCase();
    final bool isCod = upper == 'COD';
    final String label = switch (upper) {
      'COD' => 'Cash on Delivery',
      'ONLINE' => 'Paid online',
      'WALLET' => 'Paid via wallet',
      _ => paymentMethod,
    };
    final Color color = isCod ? AppColors.warning : AppColors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isCod ? Icons.payments_outlined : Icons.check_circle_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(label, style: AppTypography.micro.copyWith(color: color)),
        ],
      ),
    );
  }
}
