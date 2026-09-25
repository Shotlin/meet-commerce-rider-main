import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/shared/widgets/app_offline_banner.dart';

/// Minimal stub widget shown as the child of [AppOfflineBanner].
const Widget _child = Placeholder();

/// Builds a [ProviderScope] with a fake [isOfflineStreamProvider].
Widget _buildTestApp({required Stream<bool> offlineStream}) {
  return ProviderScope(
    overrides: [
      isOfflineStreamProvider.overrideWith((Ref ref) => offlineStream),
    ],
    child: const MaterialApp(home: Scaffold(body: _BannerUnderTest())),
  );
}

/// A minimal consumer that wires [isOfflineStreamProvider] → [AppOfflineBanner].
class _BannerUnderTest extends ConsumerWidget {
  const _BannerUnderTest();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isOffline =
        ref.watch<AsyncValue<bool>>(isOfflineStreamProvider).value ?? false;
    return AppOfflineBanner(isOffline: isOffline, child: _child);
  }
}

void main() {
  group('AppOfflineBanner widget', () {
    testWidgets('does not show banner when online (stream emits false)', (
      WidgetTester tester,
    ) async {
      final StreamController<bool> controller =
          StreamController<bool>.broadcast();

      await tester.pumpWidget(_buildTestApp(offlineStream: controller.stream));
      controller.add(false);
      await tester.pump();

      // The banner's offline strip contains the wifi_off icon.
      // The icon is still in the tree but at opacity 0 (AnimatedOpacity).
      final AnimatedOpacity opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byIcon(Icons.wifi_off),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0.0);

      await controller.close();
    });

    testWidgets('shows banner when offline (stream emits true)', (
      WidgetTester tester,
    ) async {
      final StreamController<bool> controller =
          StreamController<bool>.broadcast();

      await tester.pumpWidget(_buildTestApp(offlineStream: controller.stream));
      controller.add(true);
      await tester.pump();

      // AnimatedSlide/Opacity won't be fully settled yet; pump a frame.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);

      await controller.close();
    });

    testWidgets('banner disappears when connectivity is restored', (
      WidgetTester tester,
    ) async {
      final StreamController<bool> controller =
          StreamController<bool>.broadcast();

      await tester.pumpWidget(_buildTestApp(offlineStream: controller.stream));

      // Go offline.
      controller.add(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);

      // Restore connectivity.
      controller.add(false);
      await tester.pump();
      // The AnimatedOpacity should eventually make the icon invisible.
      await tester.pump(const Duration(milliseconds: 300));

      // After the animation completes the banner is still in the tree
      // but opacity 0 and IgnorePointer covers it. We verify the
      // isOffline flag fed to the banner is now false by checking the
      // icon is no longer visually present (opacity = 0).
      final AnimatedOpacity animatedOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(AppOfflineBanner),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(animatedOpacity.opacity, 0.0);

      await controller.close();
    });

    testWidgets('starts without banner for an empty stream (defaults online)', (
      WidgetTester tester,
    ) async {
      final StreamController<bool> controller = StreamController<bool>();

      await tester.pumpWidget(_buildTestApp(offlineStream: controller.stream));
      await tester.pump();

      // No emission yet → default null → banner hidden.
      final AnimatedOpacity animatedOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(AppOfflineBanner),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(animatedOpacity.opacity, 0.0);

      await controller.close();
    });
  });
}
