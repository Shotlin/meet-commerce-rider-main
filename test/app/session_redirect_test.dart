import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/app/router.dart';
import 'package:meet_commerce_rider_main/features/auth/application/session_state.dart';

/// Phase 5 acceptance: session-level navigation gates.
///
/// Matrix: "unapproved rider is routed to approval flow" — and the
/// corollary that an unverified rider can never be left on /home or any
/// operational screen, while an unauthenticated rider can never reach any
/// screen but login.
void main() {
  const SessionState unknown = SessionState.unknown();
  const SessionState unauthenticated = SessionState(
    phase: SessionPhase.unauthenticated,
  );
  const SessionState unverified = SessionState(phase: SessionPhase.unverified);
  const SessionState approved = SessionState(phase: SessionPhase.approved);

  const List<String> operationalRoutes = <String>[
    AppRoutes.home,
    AppRoutes.active,
    AppRoutes.qrScan,
    AppRoutes.earnings,
    AppRoutes.payoutHistory,
    AppRoutes.history,
    AppRoutes.profile,
    AppRoutes.settings,
    AppRoutes.editProfile,
    AppRoutes.splash,
    AppRoutes.login,
    AppRoutes.otp,
  ];

  group('Unknown session (cold start)', () {
    test('stays on splash while already on splash', () {
      expect(
        computeSessionRedirect(session: unknown, location: AppRoutes.splash),
        isNull,
      );
    });

    test('any other location is forced back to splash', () {
      for (final String location in operationalRoutes) {
        if (location == AppRoutes.splash) continue; // covered above
        expect(
          computeSessionRedirect(session: unknown, location: location),
          AppRoutes.splash,
          reason: 'unresolved session must not expose $location',
        );
      }
    });
  });

  group('Unauthenticated session', () {
    test('may stay on login and OTP', () {
      expect(
        computeSessionRedirect(
          session: unauthenticated,
          location: AppRoutes.login,
        ),
        isNull,
      );
      expect(
        computeSessionRedirect(
          session: unauthenticated,
          location: AppRoutes.otp,
        ),
        isNull,
      );
    });

    test('is forced to login from every other route', () {
      for (final String location in <String>[
        AppRoutes.splash,
        AppRoutes.approval,
        AppRoutes.home,
        AppRoutes.active,
        AppRoutes.profile,
      ]) {
        expect(
          computeSessionRedirect(session: unauthenticated, location: location),
          AppRoutes.login,
          reason: 'signed-out rider must land on login from $location',
        );
      }
    });
  });

  group('Unverified session (approval gate)', () {
    test('is routed to approval from home (matrix: unapproved rider '
        'is routed to approval flow)', () {
      expect(
        computeSessionRedirect(session: unverified, location: AppRoutes.home),
        AppRoutes.approval,
      );
    });

    test('stays on approval', () {
      expect(
        computeSessionRedirect(
          session: unverified,
          location: AppRoutes.approval,
        ),
        isNull,
      );
    });

    test('is pulled off every operational and auth route', () {
      for (final String location in operationalRoutes) {
        expect(
          computeSessionRedirect(session: unverified, location: location),
          AppRoutes.approval,
          reason: 'unverified rider must never stay on $location',
        );
      }
    });

    test('is never redirected to home', () {
      for (final String location in operationalRoutes) {
        final String? target = computeSessionRedirect(
          session: unverified,
          location: location,
        );
        expect(
          target,
          isNot(AppRoutes.home),
          reason: 'unverified rider must never reach $location → home',
        );
      }
    });
  });

  group('Approved session', () {
    test('is routed to home from splash, login and approval', () {
      for (final String location in <String>[
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.otp,
        AppRoutes.approval,
      ]) {
        expect(
          computeSessionRedirect(session: approved, location: location),
          AppRoutes.home,
          reason: 'approved rider leaves $location for home',
        );
      }
    });

    test('stays on home and operational screens without a batch', () {
      for (final String location in <String>[
        AppRoutes.home,
        AppRoutes.profile,
        AppRoutes.settings,
        AppRoutes.earnings,
        AppRoutes.history,
      ]) {
        expect(
          computeSessionRedirect(session: approved, location: location),
          isNull,
        );
      }
    });

    test('with an active delivery still awaiting pickup, is kept on the '
        'scanner flow', () {
      expect(
        computeSessionRedirect(
          session: approved,
          location: AppRoutes.home,
          hasActiveDelivery: true,
          needsPickup: true,
        ),
        AppRoutes.qrScan,
      );
      expect(
        computeSessionRedirect(
          session: approved,
          location: AppRoutes.active,
          hasActiveDelivery: true,
          needsPickup: true,
        ),
        AppRoutes.qrScan,
        reason:
            'an unpicked-up order must not leave the rider on the '
            'delivery map',
      );
    });

    test('with a picked-up (in-transit) delivery, is kept on the delivery '
        'map', () {
      expect(
        computeSessionRedirect(
          session: approved,
          location: AppRoutes.home,
          hasActiveDelivery: true,
          needsPickup: false,
        ),
        AppRoutes.active,
      );
      expect(
        computeSessionRedirect(
          session: approved,
          location: AppRoutes.qrScan,
          hasActiveDelivery: true,
          needsPickup: false,
        ),
        AppRoutes.active,
        reason:
            'once pickup is confirmed the scanner has nothing left '
            'to scan — the rider moves to the delivery map',
      );
    });

    test('the QR scanner is exempt from its own redirect while pickup is '
        'pending', () {
      expect(
        computeSessionRedirect(
          session: approved,
          location: AppRoutes.qrScan,
          hasActiveDelivery: true,
          needsPickup: true,
        ),
        isNull,
        reason:
            'a scan-session change must not yank the rider off the '
            'scanner mid-scan',
      );
    });
  });
}
