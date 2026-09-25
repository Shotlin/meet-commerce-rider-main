import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/location/location_display_provider.dart';
import '../../../core/location/location_lifecycle_manager.dart';
import '../../../core/location/location_permission_service.dart';
import '../../../core/maps/geo_point.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_haptics.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../delivery/application/active_delivery_controller.dart';
import '../../delivery/application/delivery_socket_controller.dart';
import '../../delivery/application/offers_controller.dart';
import '../../delivery/application/pickup_session_controller.dart';
import '../../delivery/domain/assignment_status.dart';
import '../../delivery/domain/delivery_order.dart';
import '../../delivery/domain/pickup_session.dart';
import '../../delivery/domain/rider_earnings.dart';
import '../../delivery/domain/rider_profile.dart';
import '../../delivery/domain/rider_stats.dart';
import '../../delivery/domain/store_info.dart';
import '../../delivery/presentation/delivery_offer_sheet.dart';
import '../application/home_dashboard_controller.dart';
import '../application/online_toggle_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  final Set<String> _shownOfferIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureLocationIfOnline());
    });
  }

  Future<void> _ensureLocationIfOnline() async {
    if (!mounted) return;
    await ref
        .read<HomeDashboardController>(homeDashboardControllerProvider)
        .refresh();
    if (!mounted) return;
    final RiderProfile? profile = ref
        .read<HomeDashboardController>(homeDashboardControllerProvider)
        .profile;
    final bool isOnline = profile?.isOnline ?? false;
    final bool hasActiveDelivery =
        ref
            .read<ActiveDeliveryController>(activeDeliveryControllerProvider)
            .current !=
        null;
    final bool streaming = await ref
        .read<LocationLifecycleManager>(locationLifecycleManagerProvider)
        .ensureRunningIfOnline(
          isOnline: isOnline,
          hasActiveDelivery: hasActiveDelivery,
        );
    if (!mounted) return;
    // The backend already thinks this rider is online — likely from the
    // same account signed in on another device — but this device never
    // got permission to stream its own GPS, so it keeps showing whatever
    // location the last device reported. Surface it instead of failing
    // silently, with a direct path to fix it. The same prompt applies
    // when an active delivery needs tracking restored (offline riders
    // with an in-flight order keep streaming — §6).
    if ((isOnline || hasActiveDelivery) && !streaming) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "You're online but this device isn't sharing its location — enable location permission",
          ),
          action: SnackBarAction(
            label: 'Enable',
            onPressed: () => unawaited(
              ref
                  .read<LocationPermissionService>(
                    locationPermissionServiceProvider,
                  )
                  .openAppSettings(),
            ),
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _handleToggle({required bool goOnline}) async {
    final OnlineToggleController toggle = ref.read<OnlineToggleController>(
      onlineToggleControllerProvider,
    );
    final LocationLifecycleManager locationManager = ref
        .read<LocationLifecycleManager>(locationLifecycleManagerProvider);
    // Snapshot the delivery state BEFORE toggling: an active order must
    // survive a go-offline (blueprint §6 — going offline must not
    // abandon the assigned delivery; it only stops NEW offers).
    final DeliveryOrder? activeOrder = ref
        .read<ActiveDeliveryController>(activeDeliveryControllerProvider)
        .current;
    final PickupSessionController pickupSession = ref
        .read<PickupSessionController>(pickupSessionControllerProvider);
    final bool needsPickup =
        activeOrder != null &&
        pickupSession.statusFor(activeOrder.orderId) !=
            PickupScanStatus.pickedUp;

    if (goOnline) {
      await toggle.goOnline();
    } else {
      await toggle.goOffline();
    }
    if (!mounted) return;

    final OnlineToggleState s = toggle.state;
    if (s.routeToApproval) {
      toggle.clearTransientFlags();
      context.go(AppRoutes.approval);
      return;
    }
    if (s.accountSuspended) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account is suspended. Contact support for help'),
          duration: Duration(seconds: 6),
        ),
      );
      toggle.clearTransientFlags();
      return;
    }
    if (s.serviceDisabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn on location services to go online')),
      );
      toggle.clearTransientFlags();
      return;
    }
    if (s.permissionEducationNeeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required to go online'),
        ),
      );
      toggle.clearTransientFlags();
      return;
    }
    if (s.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errorMessage!)));
      toggle.clearTransientFlags();
      return;
    }

    // Successful availability change — small confirmation haptic
    // (design §24: "haptic on successful accept"-class confirmations).
    unawaited(Future<void>.sync(AppHaptics.light));

    if (s.isOnline) {
      unawaited(locationManager.onWentOnline());
    } else if (activeOrder != null) {
      // Offline with an active delivery: stop new offers, keep the
      // live tracking running for the in-flight order.
      unawaited(
        locationManager.onWentOfflineDuringDelivery(pickedUp: !needsPickup),
      );
    } else {
      unawaited(locationManager.onWentOffline());
    }

    unawaited(
      ref
          .read<HomeDashboardController>(homeDashboardControllerProvider)
          .refresh(),
    );
  }

  Future<void> _autoPresentOfferIfNeeded(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final OffersController offers = ref.read<OffersController>(
      offersControllerProvider,
    );
    final ActiveDeliveryController active = ref.read<ActiveDeliveryController>(
      activeDeliveryControllerProvider,
    );
    if (active.current != null) return;
    for (final DeliveryOrder offer in offers.offers) {
      if (_shownOfferIds.contains(offer.orderId)) continue;
      _shownOfferIds.add(offer.orderId);
      final OfferSheetResult result = await showDeliveryOfferSheet(
        context,
        offer,
      );
      if (!context.mounted) return;
      _showOfferFeedback(context, result);
      return;
    }
  }

  /// Surfaces the offer sheet's outcome: the lost-race message
  /// ("Order taken by another rider", §9 item 7) and decline
  /// acknowledgement, so a decision never ends in silence.
  void _showOfferFeedback(BuildContext context, OfferSheetResult result) {
    final String? message = switch (result.outcome) {
      OfferSheetOutcome.accepted => null,
      OfferSheetOutcome.declined => result.message,
      OfferSheetOutcome.dismissed => result.message,
    };
    if (message == null || message.isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// "Continue delivery" always lands on the delivery map: its
  /// toStore phase is the pickup navigation screen (§11) whose scan
  /// CTA opens the verified pickup flow.
  String _activeDeliveryRoute(DeliveryOrder order) => AppRoutes.active;

  @override
  Widget build(BuildContext context) {
    final HomeDashboardController dashboard = ref
        .watch<HomeDashboardController>(homeDashboardControllerProvider);
    final OnlineToggleController toggle = ref.watch<OnlineToggleController>(
      onlineToggleControllerProvider,
    );
    final OffersController offers = ref.watch<OffersController>(
      offersControllerProvider,
    );
    final ActiveDeliveryController active = ref.watch<ActiveDeliveryController>(
      activeDeliveryControllerProvider,
    );
    final LocationDisplay? locationDisplay = ref
        .watch(locationDisplayProvider)
        .value;
    final StoreInfo? store = ref
        .watch<AsyncValue<StoreInfo>>(storeInfoProvider)
        .value;

    final RiderProfile? profile = dashboard.profile;
    if (profile != null && profile.isApproved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read<OnlineToggleController>(onlineToggleControllerProvider)
            .syncFromProfile(isOnline: profile.isOnline);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoPresentOfferIfNeeded(context, ref));
    });

    // Single active delivery (blueprint §10): when one exists it
    // dominates the screen (requirement §7) — the busy hero and the
    // order card below it, and no competing offers section.
    final DeliveryOrder? activeOrder = active.current;
    final bool busy = activeOrder != null;
    final bool showOffers = !busy;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.black,
          onRefresh: () => Future.wait(<Future<void>>[
            dashboard.refresh(),
            ref
                .read<DeliverySocketController>(
                  deliverySocketControllerProvider,
                )
                .refreshOrders(),
          ]),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: <Widget>[
              // ── Header ────────────────────────────────────────────────
              _HomeHeader(
                profile: profile,
                profileLoading: dashboard.profileLoading,
                storeName: store?.name,
              ),
              const SizedBox(height: AppDimensions.lg),

              // ── Availability hero (design §9) ─────────────────────────
              _AvailabilityHero(
                profileLoading: dashboard.profileLoading,
                toggleState: toggle.state,
                locationDisplay: locationDisplay,
                hasActiveDelivery: busy,
                needsPickup: busy
                    ? ref
                              .watch<PickupSessionController>(
                                pickupSessionControllerProvider,
                              )
                              .statusFor(activeOrder.orderId) !=
                          PickupScanStatus.pickedUp
                    : false,
                activeOrder: activeOrder,
                onToggle: (bool wantOnline) =>
                    _handleToggle(goOnline: wantOnline),
                onContinueDelivery: busy
                    ? () => context.push(_activeDeliveryRoute(activeOrder))
                    : null,
              ),
              const SizedBox(height: AppDimensions.lg),

              // ── Active order card (dominates while busy) ──────────────
              if (busy) ...<Widget>[
                _ActiveOrderCard(
                  order: activeOrder,
                  onTap: () => context.push(_activeDeliveryRoute(activeOrder)),
                ),
                const SizedBox(height: AppDimensions.lg),
              ],

              // ── Quick metrics (design §9: clean 2×2, real data only) ──
              _MetricsGrid(
                stats: dashboard.stats,
                earningsToday: dashboard.earningsToday,
                profile: profile,
                statsLoading: dashboard.statsLoading,
                statsError: dashboard.statsError,
                earningsLoading: dashboard.earningsLoading,
                earningsError: dashboard.earningsError,
                onRetry: () => unawaited(dashboard.refresh()),
              ),
              const SizedBox(height: AppDimensions.lg),

              // ── Waiting state / offers ────────────────────────────────
              // While busy, new offers must not compete for attention
              // (requirement §7) — the offers section only renders when
              // the rider is idle.
              if (showOffers)
                _OffersSection(
                  offers: offers.offers,
                  ordersLoading: dashboard.ordersLoading,
                  ordersError: dashboard.ordersError,
                  isOnline: toggle.state.isOnline,
                  onRetry: () => unawaited(dashboard.refresh()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String formatRupees(double value) => _money.format(value);
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — greeting + store/zone line (left), avatar (right). Design §9.
// ─────────────────────────────────────────────────────────────────────────────

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.profile,
    required this.profileLoading,
    required this.storeName,
  });

  final RiderProfile? profile;
  final bool profileLoading;
  final String? storeName;

  static String _greetingForNow() {
    final int hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final String firstName = (profile?.name?.isNotEmpty ?? false)
        ? profile!.name!.split(' ').first
        : 'Rider';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (profileLoading && profile == null)
                Skeleton.line(height: 26, width: 200)
              else ...<Widget>[
                Text(
                  '${_greetingForNow()},',
                  style: AppTypography.body.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  firstName,
                  style: AppTypography.title.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
              ],
              if (storeName != null && storeName!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.storefront_outlined,
                      size: 14,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        storeName!,
                        style: AppTypography.micro.copyWith(
                          color: AppColors.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppDimensions.md),
        _Avatar(avatarUrl: profile?.avatarUrl, firstName: firstName),
      ],
    );
  }
}

/// Rider avatar — the profile photo when present, a brand-tinted initials
/// circle otherwise. Tapping opens the profile tab.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatarUrl, required this.firstName});

  final String? avatarUrl;
  final String firstName;

  @override
  Widget build(BuildContext context) {
    final String initials = firstName.isNotEmpty
        ? firstName[0].toUpperCase()
        : 'R';
    final Widget fallback = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.brandSoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: AppTypography.label.copyWith(color: AppColors.brand),
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(AppDimensions.chipRadius),
      onTap: () => context.go(AppRoutes.profile),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: ClipOval(
          child: avatarUrl == null || avatarUrl!.isEmpty
              ? fallback
              : Image.network(
                  avatarUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                      fallback,
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Availability hero (design §9) — one card, three states:
//
// - OFFLINE: white card, red `Go Online` primary.
// - ONLINE:  white card + green badge, "waiting near your store",
//            location freshness line, secondary `Go Offline`.
// - BUSY:    soft-red active state (works while online AND for the
//            Phase 6 offline-with-active-delivery case), pickup/drop
//            status, `Continue Delivery` primary; `Stop new orders`
//            secondary only while dispatch-online.
// ─────────────────────────────────────────────────────────────────────────────

class _AvailabilityHero extends StatelessWidget {
  const _AvailabilityHero({
    required this.profileLoading,
    required this.toggleState,
    required this.locationDisplay,
    required this.hasActiveDelivery,
    required this.needsPickup,
    required this.activeOrder,
    required this.onToggle,
    required this.onContinueDelivery,
  });

  final bool profileLoading;
  final OnlineToggleState toggleState;
  final LocationDisplay? locationDisplay;

  /// Whether one active delivery exists (blueprint §10). Drives the
  /// busy state regardless of the dispatch-online flag — going offline
  /// during an active delivery must not abandon it (§6).
  final bool hasActiveDelivery;

  /// Whether the active order still needs pickup verification
  /// (busy state's pickup/drop line + continue target).
  final bool needsPickup;
  final DeliveryOrder? activeOrder;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onContinueDelivery;

  @override
  Widget build(BuildContext context) {
    if (profileLoading && !hasActiveDelivery) {
      return Skeleton.box(height: 180, radius: AppDimensions.heroCardRadius);
    }

    final bool isOnline = toggleState.isOnline;
    final bool actionBusy = toggleState.isBusy;

    // Busy visuals take priority — the delivery lifecycle outranks the
    // dispatch flag (§6).
    if (hasActiveDelivery) {
      return _BusyHero(
        state: toggleState,
        order: activeOrder,
        needsPickup: needsPickup,
        isOnline: isOnline,
        actionBusy: actionBusy,
        onToggle: onToggle,
        onContinueDelivery: onContinueDelivery,
      );
    }
    if (isOnline) {
      return _OnlineHero(
        state: toggleState,
        locationDisplay: locationDisplay,
        actionBusy: actionBusy,
        onToggle: onToggle,
      );
    }
    return _OfflineHero(
      state: toggleState,
      actionBusy: actionBusy,
      onToggle: onToggle,
    );
  }
}

/// Shared hero shell so all three states keep the same geometry
/// (20 px radius, 18 px padding, chip row → headline → support line →
/// actions).
class _HeroShell extends StatelessWidget {
  const _HeroShell({
    required this.background,
    required this.borderColor,
    required this.children,
  });

  final Color background;
  final Color borderColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.easing,
      padding: const EdgeInsets.all(AppDimensions.heroCardPadding),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDimensions.heroCardRadius),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _OfflineHero extends StatelessWidget {
  const _OfflineHero({
    required this.state,
    required this.actionBusy,
    required this.onToggle,
  });

  final OnlineToggleState state;
  final bool actionBusy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return _HeroShell(
      background: AppColors.white,
      borderColor: AppColors.border,
      children: <Widget>[
        Row(
          children: <Widget>[
            const StatusChip(label: 'OFFLINE', tone: StatusTone.offline),
            const Spacer(),
            if (actionBusy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          "You're offline",
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
        const SizedBox(height: 6),
        Text(
          'Go online to start receiving orders near your store.',
          style: AppTypography.body.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppDimensions.lg),
        AppButton(
          label: 'Go online',
          isLoading: actionBusy,
          variant: AppButtonVariant.primary,
          onPressed: actionBusy ? null : () => onToggle(true),
        ),
      ],
    );
  }
}

class _OnlineHero extends StatelessWidget {
  const _OnlineHero({
    required this.state,
    required this.locationDisplay,
    required this.actionBusy,
    required this.onToggle,
  });

  final OnlineToggleState state;
  final LocationDisplay? locationDisplay;
  final bool actionBusy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return _HeroShell(
      background: AppColors.white,
      borderColor: AppColors.border,
      children: <Widget>[
        Row(
          children: <Widget>[
            const StatusChip(label: 'ONLINE', tone: StatusTone.online),
            const Spacer(),
            if (actionBusy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          "You're online",
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
        const SizedBox(height: 6),
        Text(
          'Waiting for an order near your store.',
          style: AppTypography.body.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppDimensions.sm),
        _LocationFreshnessLine(display: locationDisplay),
        const SizedBox(height: AppDimensions.lg),
        AppButton(
          label: 'Go offline',
          isLoading: actionBusy,
          variant: AppButtonVariant.secondary,
          onPressed: actionBusy ? null : () => onToggle(false),
        ),
      ],
    );
  }
}

class _BusyHero extends StatelessWidget {
  const _BusyHero({
    required this.state,
    required this.order,
    required this.needsPickup,
    required this.isOnline,
    required this.actionBusy,
    required this.onToggle,
    required this.onContinueDelivery,
  });

  final OnlineToggleState state;
  final DeliveryOrder? order;
  final bool needsPickup;
  final bool isOnline;
  final bool actionBusy;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onContinueDelivery;

  @override
  Widget build(BuildContext context) {
    final String statusLine = needsPickup
        ? 'Pick up from ${order?.storeAddress.name ?? 'the store'}'
        : 'Deliver to ${order?.customerAddress.name.isNotEmpty ?? false ? order!.customerAddress.name : 'the customer'}';

    return _HeroShell(
      // Design §9 busy: FreshCuts soft-red active state — red carries
      // "this is live and needs you" without an alarm look.
      background: AppColors.brandSoft,
      borderColor: AppColors.brandBorder,
      children: <Widget>[
        Row(
          children: <Widget>[
            const StatusChip(
              label: '1 ACTIVE DELIVERY',
              tone: StatusTone.danger,
            ),
            const Spacer(),
            if (actionBusy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.brand),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          needsPickup ? 'Heading to pickup' : 'In transit',
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
        const SizedBox(height: 6),
        Text(
          statusLine,
          style: AppTypography.body.copyWith(color: AppColors.graphite),
        ),
        // Going offline with an active delivery (§6): the rider keeps
        // navigating this order; only new offers stop. Say so instead of
        // pretending the delivery is paused.
        if (!isOnline) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            'Not accepting new orders. Your active delivery continues.',
            style: AppTypography.micro.copyWith(color: AppColors.muted),
          ),
        ],
        const SizedBox(height: AppDimensions.lg),
        AppButton(
          label: 'Continue delivery',
          variant: AppButtonVariant.primary,
          onPressed: onContinueDelivery,
        ),
        if (isOnline) ...<Widget>[
          const SizedBox(height: AppDimensions.sm),
          AppButton(
            label: 'Stop new orders',
            isLoading: actionBusy,
            variant: AppButtonVariant.secondary,
            onPressed: actionBusy ? null : () => onToggle(false),
          ),
        ],
      ],
    );
  }
}

/// Compact location freshness line (design §9 "location freshness line"):
/// reverse-geocoded area when available, coordinates otherwise, and an
/// honest "Locating…" while the first fix or lookup is pending.
class _LocationFreshnessLine extends StatelessWidget {
  const _LocationFreshnessLine({required this.display});

  final LocationDisplay? display;

  @override
  Widget build(BuildContext context) {
    final String label;
    if (display == null) {
      label = 'Locating…';
    } else {
      final GeoPoint pos = display!.position;
      final String coords =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      label = display!.areaName != null && display!.areaName!.isNotEmpty
          ? '${display!.areaName!} · $coords'
          : coords;
    }

    return Row(
      children: <Widget>[
        Icon(
          display == null ? Icons.location_searching : Icons.location_on,
          size: 13,
          color: AppColors.success,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            style: AppTypography.micro.copyWith(color: AppColors.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active order card — the order's specifics under the busy hero.
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order, required this.onTap});

  final DeliveryOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool inTransit = order.assignmentStatus == AssignmentStatus.inTransit;
    final String label = inTransit ? 'IN TRANSIT' : 'TO STORE';
    final StatusTone tone = inTransit ? StatusTone.info : StatusTone.pending;

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppDimensions.heroCardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.heroCardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppDimensions.denseCardPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.heroCardRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delivery_dining,
                  size: 24,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Order #${order.orderNumber}',
                      style: AppTypography.label.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_HomeScreenState.formatRupees(order.riderEarning)} earning'
                      ' · ${order.storeAddress.name} → ${order.customerAddress.name.isNotEmpty ? order.customerAddress.name : order.customerAddress.address}',
                      style: AppTypography.micro.copyWith(
                        color: AppColors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusChip(label: label, tone: tone),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick metrics (design §9: 2×2, no analytics dashboard) — every value is
// real backend data. Cash-in-hand joins this grid in Phase 14 when the
// collection ledger exists; Pending payout fills the fourth tile until then.
// ─────────────────────────────────────────────────────────────────────────────

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.stats,
    required this.earningsToday,
    required this.profile,
    required this.statsLoading,
    required this.statsError,
    required this.earningsLoading,
    required this.earningsError,
    required this.onRetry,
  });

  final RiderStats? stats;
  final RiderEarnings? earningsToday;
  final RiderProfile? profile;
  final bool statsLoading;
  final String? statsError;
  final bool earningsLoading;
  final String? earningsError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (statsError != null && earningsError != null && stats == null) {
      return ErrorState(
        title: 'Could not load stats',
        body: statsError,
        onRetry: onRetry,
      );
    }
    if ((statsLoading && stats == null) ||
        (earningsLoading && earningsToday == null)) {
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Skeleton.box(height: 76)),
              const SizedBox(width: AppDimensions.md),
              Expanded(child: Skeleton.box(height: 76)),
            ],
          ),
          const SizedBox(height: AppDimensions.md),
          Row(
            children: <Widget>[
              Expanded(child: Skeleton.box(height: 76)),
              const SizedBox(width: AppDimensions.md),
              Expanded(child: Skeleton.box(height: 76)),
            ],
          ),
        ],
      );
    }

    final double earningsValue = earningsToday?.totalEarnings ?? 0;
    final int delivered = stats?.deliveredToday ?? 0;
    final double rating = (profile?.rating ?? stats?.rating ?? 0).toDouble();
    final double pendingPayout = earningsToday?.pendingPayout ?? 0;
    final bool commissionEnabled = profile?.commissionEnabled ?? true;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: commissionEnabled
                  ? _StatTile(
                      label: "Today's earnings",
                      value: _HomeScreenState.formatRupees(earningsValue),
                      icon: Icons.payments_outlined,
                      iconColor: AppColors.success,
                    )
                  : const _StatTile(
                      label: 'Pay type',
                      value: 'Salary',
                      icon: Icons.badge_outlined,
                      iconColor: AppColors.success,
                    ),
            ),
            const SizedBox(width: AppDimensions.md),
            Expanded(
              child: _StatTile(
                label: 'Delivered today',
                value: delivered.toString(),
                icon: Icons.local_shipping_outlined,
                iconColor: AppColors.charcoal,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatTile(
                label: 'Rating',
                value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                icon: Icons.star_rounded,
                iconColor: AppColors.warning,
              ),
            ),
            const SizedBox(width: AppDimensions.md),
            Expanded(
              child: _StatTile(
                label: 'Pending payout',
                value: _HomeScreenState.formatRupees(pendingPayout),
                icon: Icons.account_balance_wallet_outlined,
                iconColor: AppColors.info,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Individual stat tile — a layout that never truncates values.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // FittedBox scales the value down gracefully if needed
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: AppTypography.heading.copyWith(
                      color: AppColors.charcoal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offers / waiting state
// ─────────────────────────────────────────────────────────────────────────────

class _OffersSection extends StatelessWidget {
  const _OffersSection({
    required this.offers,
    required this.ordersLoading,
    required this.ordersError,
    required this.isOnline,
    required this.onRetry,
  });

  final List<DeliveryOrder> offers;
  final bool ordersLoading;
  final String? ordersError;
  final bool isOnline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (ordersLoading && offers.isEmpty) {
      return Column(
        children: <Widget>[
          Skeleton.box(height: 96),
          const SizedBox(height: 8),
          Skeleton.box(height: 96),
        ],
      );
    }
    if (ordersError != null && offers.isEmpty) {
      return ErrorState(
        title: 'Could not load orders',
        body: ordersError,
        onRetry: onRetry,
      );
    }
    if (offers.isEmpty) {
      // Design §9 idle visual: restrained icon + concise copy. When
      // online this is the canonical "ready and waiting" state the
      // requirements call for; offline the hero already carries the
      // primary action, so this stays neutral.
      return EmptyState(
        icon: isOnline ? Icons.hourglass_empty : Icons.delivery_dining,
        title: isOnline ? "You're online and ready" : 'You are offline',
        body: isOnline
            ? 'Waiting for an eligible nearby order. You will hear a sound when one arrives.'
            : 'Go online to start receiving orders.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'NEW OFFERS',
          style: AppTypography.micro.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        for (final DeliveryOrder offer in offers) ...<Widget>[
          _OfferRow(offer: offer),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.offer});

  final DeliveryOrder offer;

  @override
  Widget build(BuildContext context) {
    Future<void> open() async {
      final OfferSheetResult result = await showDeliveryOfferSheet(
        context,
        offer,
      );
      if (!context.mounted) return;
      final String? message = switch (result.outcome) {
        OfferSheetOutcome.accepted => null,
        OfferSheetOutcome.declined => result.message,
        OfferSheetOutcome.dismissed => result.message,
      };
      if (message == null || message.isEmpty) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: () => unawaited(open()),
        child: Container(
          padding: const EdgeInsets.all(AppDimensions.denseCardPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delivery_dining,
                  size: 22,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _HomeScreenState.formatRupees(offer.riderEarning),
                      style: AppTypography.heading.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      offer.storeAddress.name,
                      style: AppTypography.body.copyWith(
                        color: AppColors.charcoal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      offer.customerAddress.name.isNotEmpty
                          ? offer.customerAddress.name
                          : offer.customerAddress.address,
                      style: AppTypography.micro.copyWith(
                        color: AppColors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
