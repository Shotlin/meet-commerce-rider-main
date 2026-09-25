import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/session_controller.dart';
import '../features/auth/application/session_state.dart';
import '../features/auth/presentation/otp_screen.dart';
import '../features/auth/presentation/phone_login_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/delivery/application/active_delivery_controller.dart';
import '../features/delivery/presentation/active_delivery_map_screen.dart';
import '../features/delivery/presentation/qr_scan_screen.dart';
import '../features/earnings/presentation/earnings_screen.dart';
import '../features/earnings/presentation/payout_history_screen.dart';
import '../features/history/presentation/delivery_history_screen.dart';
import '../features/home/presentation/rider_shell.dart';
import '../features/onboarding/presentation/rider_approval_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/settings_screen.dart';
import '../core/providers.dart';

/// Path constants used by the rider app.
abstract final class AppRoutes {
  /// Splash + auth gate.
  static const String splash = '/';

  /// Phone OTP login start.
  static const String login = '/login';

  /// OTP entry screen.
  static const String otp = '/otp';

  /// Rider approval screen (unverified rider).
  static const String approval = '/approval';

  /// Home shell (approved rider).
  static const String home = '/home';

  /// Active delivery (map + action sheets).
  static const String active = '/active';

  /// Full-screen QR scanner for invoice pickup codes.
  static const String qrScan = '/qr-scan';

  /// Earnings screen.
  static const String earnings = '/earnings';

  /// Payout history screen.
  static const String payoutHistory = '/payout-history';

  /// Delivery history screen.
  static const String history = '/history';

  /// Profile screen.
  static const String profile = '/profile';

  /// Settings screen.
  static const String settings = '/settings';

  /// Edit profile screen.
  static const String editProfile = '/edit-profile';
}

/// Pure navigation decision behind the router's session-level gates
/// (splash → login → approval → home), plus the active-batch rule R26.2.
///
/// Extracted from the `redirect` closure in [buildAppRouter] so the gate
/// matrix — notably "unapproved rider is routed to approval flow" and the
/// guarantee that an unverified rider can never land on /home — is unit-testable
/// without booting the whole controller graph.
///
/// Inputs:
/// - [session] — current [SessionState] (phase decides the gate).
/// - [location] — the router's `state.matchedLocation`.
/// - [hasActiveDelivery] — whether the rider has a single active order
///   (blueprint §10: at most one accepted/picked-up/in-transit order).
///
/// Returns the redirect target, or `null` to allow the current location.
@visibleForTesting
String? computeSessionRedirect({
  required SessionState session,
  required String location,
  bool hasActiveDelivery = false,
}) {
  // While we don't yet know the session, keep the splash screen.
  if (!session.isResolved) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }

  final bool onAuthScreen =
      location == AppRoutes.login || location == AppRoutes.otp;

  if (session.isUnauthenticated) {
    return onAuthScreen ? null : AppRoutes.login;
  }
  if (session.isUnverified) {
    return location == AppRoutes.approval ? null : AppRoutes.approval;
  }
  if (session.isApproved) {
    // Active-delivery rule (R26.2, single-order form — blueprint §10):
    // whenever the rider has an active order, keep them inside the
    // delivery flow rather than /home — a hot restart, push
    // notification, or tab switch should never leave a live delivery
    // running in the background unattended.
    //
    // Phase 11: the rider always lands on /active — the map screen's
    // toStore phase IS the pickup navigation screen (§11: heading-to-
    // store status, store card, arrival state, scan CTA); pickup
    // verification happens on /qr-scan, which is *pushed* from there
    // and therefore exempt from this redirect — a scan-session state
    // change (e.g. marking the order verified) must not yank the
    // rider off the camera mid-scan.
    if (hasActiveDelivery) {
      if (location == AppRoutes.qrScan) {
        return null;
      }
      if (location != AppRoutes.active) {
        return AppRoutes.active;
      }
    }
    if (onAuthScreen ||
        location == AppRoutes.splash ||
        location == AppRoutes.approval) {
      return AppRoutes.home;
    }
    return null;
  }
  return null;
}

/// Builds the global [GoRouter] used by the app, wired to the
/// [SessionController] so navigation tracks session changes.
GoRouter buildAppRouter(WidgetRef ref) {
  final SessionController session = ref.read<SessionController>(
    sessionControllerProvider,
  );
  final ActiveDeliveryController active = ref.read<ActiveDeliveryController>(
    activeDeliveryControllerProvider,
  );
  // Listenable that fires whenever the session or the active order
  // changes so the redirect rule re-evaluates. (Pickup-scan state does
  // not change the redirect target any more — the scanner is a pushed
  // screen exempt from this gate.)
  final Listenable refresh = Listenable.merge(<Listenable>[
    session,
    active,
  ]);
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      return computeSessionRedirect(
        session: session.state,
        location: state.matchedLocation,
        hasActiveDelivery: active.current != null,
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (BuildContext context, GoRouterState state) =>
            const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (BuildContext context, GoRouterState state) =>
            const PhoneLoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (BuildContext context, GoRouterState state) =>
            const OtpScreen(),
      ),
      GoRoute(
        path: AppRoutes.approval,
        builder: (BuildContext context, GoRouterState state) =>
            const RiderApprovalScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (BuildContext context, GoRouterState state) =>
            const RiderShell(),
      ),
      GoRoute(
        path: AppRoutes.active,
        builder: (BuildContext context, GoRouterState state) =>
            const ActiveDeliveryMapScreen(),
      ),
      GoRoute(
        path: AppRoutes.qrScan,
        builder: (BuildContext context, GoRouterState state) =>
            const QrScanScreen(),
      ),
      GoRoute(
        path: AppRoutes.earnings,
        builder: (BuildContext context, GoRouterState state) =>
            const EarningsScreen(),
      ),
      GoRoute(
        path: AppRoutes.payoutHistory,
        builder: (BuildContext context, GoRouterState state) =>
            const PayoutHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.history,
        builder: (BuildContext context, GoRouterState state) =>
            const DeliveryHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (BuildContext context, GoRouterState state) =>
            const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (BuildContext context, GoRouterState state) =>
            const EditProfileScreen(),
      ),
    ],
  );
}
