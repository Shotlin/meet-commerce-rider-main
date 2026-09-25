import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/theme/app_theme.dart';
import 'package:meet_commerce_rider_main/features/auth/presentation/splash_screen.dart';

/// Smoke test that the splash screen renders inside a ProviderScope.
///
/// We render the splash widget directly rather than booting the full
/// router, because the router redirect awaits the live SessionController
/// resolving against the backend; that's covered by integration tests.
void main() {
  testWidgets('Splash screen renders the Freashcut Rider title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.light(), home: const SplashScreen()),
      ),
    );

    expect(find.text('Freashcut Rider'), findsOneWidget);
    expect(find.text('Setting things up…'), findsOneWidget);
  });
}
