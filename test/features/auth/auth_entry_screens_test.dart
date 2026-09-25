import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/app/router.dart';
import 'package:meet_commerce_rider_main/core/config/env.dart';
import 'package:meet_commerce_rider_main/core/config/flavor.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/core/storage/secure_token_store.dart';
import 'package:meet_commerce_rider_main/core/theme/app_theme.dart';
import 'package:meet_commerce_rider_main/features/auth/data/auth_api.dart';
import 'package:meet_commerce_rider_main/features/auth/data/auth_repository.dart';
import 'package:meet_commerce_rider_main/features/auth/presentation/otp_screen.dart';
import 'package:meet_commerce_rider_main/features/auth/presentation/phone_login_screen.dart';
import 'package:meet_commerce_rider_main/features/auth/presentation/splash_screen.dart';
import 'package:meet_commerce_rider_main/shared/widgets/brand_mark.dart';

/// Phase 5 acceptance: entry surfaces + dev-affordance gating.
///
/// Design §4/§7 requires that developer affordances (demo quick login, the
/// backend-echoed OTP) are structurally absent from staging and production
/// builds. These tests drive the real screens through the real controller and
/// repository against a mocked transport, so the gating is proven end-to-end
/// rather than by source inspection.
class _MockAuthApi extends Mock implements AuthApi {}

/// Minimal router exposing only the login → OTP leg, so `context.go` inside
/// the screens resolves without booting the full session-aware app router.
GoRouter _buildRouter({String initialLocation = AppRoutes.login}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
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
    ],
  );
}

/// Pumps the phone-login screen with [flavor]'s env and a repository backed
/// by the mocked [api].
Future<void> _pumpLogin(
  WidgetTester tester, {
  required AppFlavor flavor,
  required AuthApi api,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        envProvider.overrideWithValue(Env.forFlavor(flavor)),
        authRepositoryProvider.overrideWithValue(
          AuthRepository(api: api, tokenStore: InMemoryTokenStore()),
        ),
      ],
      child: MaterialApp.router(routerConfig: _buildRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mocks `sendOtp` to echo a dev OTP the way the backend does in dev, then
/// walks the rider from login to the OTP screen.
Future<void> _reachOtpScreen(
  WidgetTester tester, {
  required AppFlavor flavor,
}) async {
  final _MockAuthApi api = _MockAuthApi();
  // The repository canonicalizes to +91 before hitting the transport; stub
  // both forms so the test fails only if the contract itself changes.
  when(
    () => api.sendOtp(phone: '+919876543210'),
  ).thenAnswer((_) async => const SendOtpResult(devOtp: '123456'));
  when(
    () => api.sendOtp(phone: '9876543210'),
  ).thenAnswer((_) async => const SendOtpResult(devOtp: '123456'));

  await _pumpLogin(tester, flavor: flavor, api: api);
  await tester.enterText(find.byType(TextField).first, '9876543210');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  expect(find.byType(OtpScreen), findsOneWidget);
}

void main() {
  group('Env dev-affordance gating', () {
    test('dev flavor enables dev affordances', () {
      expect(Env.forFlavor(AppFlavor.dev).enableDevAffordances, isTrue);
    });

    test('staging flavor disables dev affordances', () {
      final Env env = Env.forFlavor(AppFlavor.staging);
      expect(env.flavor.isDev, isFalse);
      expect(env.enableDevAffordances, isFalse);
    });

    test('production flavor disables dev affordances', () {
      final Env env = Env.forFlavor(AppFlavor.prod);
      expect(env.flavor.isDev, isFalse);
      expect(env.enableDevAffordances, isFalse);
    });
  });

  group('Login screen', () {
    testWidgets('renders the FreshCuts brand mark and Phase 5 hero copy', (
      WidgetTester tester,
    ) async {
      await _pumpLogin(tester, flavor: AppFlavor.dev, api: _MockAuthApi());

      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text('Welcome, Rider'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('dev flavor shows the demo quick-login affordance', (
      WidgetTester tester,
    ) async {
      await _pumpLogin(tester, flavor: AppFlavor.dev, api: _MockAuthApi());

      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('Login as demo rider'), findsOneWidget);
      expect(find.textContaining('OTP: 123456'), findsOneWidget);
    });

    testWidgets('staging and production hide the demo quick-login '
        'affordance entirely', (WidgetTester tester) async {
      for (final AppFlavor flavor in <AppFlavor>[
        AppFlavor.staging,
        AppFlavor.prod,
      ]) {
        await _pumpLogin(tester, flavor: flavor, api: _MockAuthApi());

        expect(
          find.text('DEMO'),
          findsNothing,
          reason: '${flavor.name} build must not show the demo section',
        );
        expect(find.text('Login as demo rider'), findsNothing);
        expect(find.textContaining('123456'), findsNothing);

        // Detach the tree before re-pumping for the next flavor.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  group('OTP screen dev-echo gating', () {
    testWidgets('dev build surfaces the echoed OTP (echo + prefill)', (
      WidgetTester tester,
    ) async {
      await _reachOtpScreen(tester, flavor: AppFlavor.dev);

      // Backend echoed data.otp → dev builds may show and prefill it.
      expect(find.textContaining('Dev OTP'), findsOneWidget);
      expect(find.text('123456'), findsOneWidget);
    });

    testWidgets('production build suppresses the echoed OTP entirely', (
      WidgetTester tester,
    ) async {
      await _reachOtpScreen(tester, flavor: AppFlavor.prod);

      // Same transport response, but the flavor gates display AND prefill.
      expect(find.textContaining('Dev OTP'), findsNothing);
      expect(find.text('123456'), findsNothing);
      final TextField field = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(field.controller?.text ?? '', isEmpty);
    });

    testWidgets('staging build suppresses the echoed OTP entirely', (
      WidgetTester tester,
    ) async {
      await _reachOtpScreen(tester, flavor: AppFlavor.staging);

      expect(find.textContaining('Dev OTP'), findsNothing);
      expect(find.text('123456'), findsNothing);
    });

    testWidgets('offers an editable-number link back to login in every '
        'flavor', (WidgetTester tester) async {
      await _reachOtpScreen(tester, flavor: AppFlavor.prod);

      expect(find.text('Wrong number? Change it'), findsOneWidget);

      await tester.tap(find.text('Wrong number? Change it'));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneLoginScreen), findsOneWidget);
    });
  });

  group('Splash screen', () {
    testWidgets('renders the FreshCuts mark above the app name', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SplashScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text('Freashcut Rider'), findsOneWidget);
      // Tear down before the session-restore timer can fire again.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
