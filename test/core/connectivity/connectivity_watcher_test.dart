import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/core/connectivity/connectivity_watcher.dart';

/// Minimal stand-in for `connectivity_plus`'s [Connectivity] singleton.
///
/// We mock Connectivity through mocktail and feed it a [StreamController]
/// of [List]<[ConnectivityResult]> so the watcher's classification and
/// debounce logic can be exercised without touching platform channels.
class _MockConnectivity extends Mock implements Connectivity {}

void main() {
  setUpAll(() {
    // Register fallback values mocktail needs when we set up `when(...)`.
    registerFallbackValue(<ConnectivityResult>[ConnectivityResult.none]);
  });

  group('ConnectivityWatcher.isOffline', () {
    late _MockConnectivity connectivity;
    late StreamController<List<ConnectivityResult>> controller;

    setUp(() {
      connectivity = _MockConnectivity();
      controller = StreamController<List<ConnectivityResult>>.broadcast(
        sync: true,
      );
      when(
        () => connectivity.onConnectivityChanged,
      ).thenAnswer((_) => controller.stream);
    });

    tearDown(() async {
      await controller.close();
    });

    test('emits true when results contain only [none]', () async {
      // Use a tiny debounce so the test stays fast and deterministic.
      final ConnectivityWatcher watcher = ConnectivityWatcher(
        connectivity,
        debounce: const Duration(milliseconds: 5),
      );

      final Future<bool> first = watcher.isOffline.first;
      controller.add(<ConnectivityResult>[ConnectivityResult.none]);

      expect(await first, isTrue);
    });

    test('emits false for wifi, mobile, or ethernet', () async {
      for (final ConnectivityResult kind in <ConnectivityResult>[
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
        ConnectivityResult.ethernet,
      ]) {
        final _MockConnectivity m = _MockConnectivity();
        final StreamController<List<ConnectivityResult>> c =
            StreamController<List<ConnectivityResult>>.broadcast(sync: true);
        when(() => m.onConnectivityChanged).thenAnswer((_) => c.stream);

        final ConnectivityWatcher watcher = ConnectivityWatcher(
          m,
          debounce: const Duration(milliseconds: 5),
        );

        final Future<bool> first = watcher.isOffline.first;
        c.add(<ConnectivityResult>[kind]);

        expect(await first, isFalse, reason: 'expected ${kind.name} -> online');
        await c.close();
      }
    });

    test(
      'emits false for mixed lists containing a connected transport',
      () async {
        final ConnectivityWatcher watcher = ConnectivityWatcher(
          connectivity,
          debounce: const Duration(milliseconds: 5),
        );

        final Future<bool> first = watcher.isOffline.first;
        controller.add(<ConnectivityResult>[
          ConnectivityResult.wifi,
          ConnectivityResult.vpn,
        ]);

        expect(await first, isFalse);
      },
    );

    test('debounces rapid flips and emits only the settled value', () async {
      const Duration debounce = Duration(milliseconds: 80);
      final ConnectivityWatcher watcher = ConnectivityWatcher(
        connectivity,
        debounce: debounce,
      );

      final List<bool> emissions = <bool>[];
      final StreamSubscription<bool> sub = watcher.isOffline.listen(
        emissions.add,
      );

      // Three quick flips within the debounce window — only the final
      // value [none] should land.
      controller.add(<ConnectivityResult>[ConnectivityResult.wifi]);
      controller.add(<ConnectivityResult>[ConnectivityResult.mobile]);
      controller.add(<ConnectivityResult>[ConnectivityResult.none]);

      await Future<void>.delayed(debounce * 3);

      expect(emissions, <bool>[true]);
      await sub.cancel();
    });

    test('suppresses duplicate consecutive offline values', () async {
      const Duration debounce = Duration(milliseconds: 20);
      final ConnectivityWatcher watcher = ConnectivityWatcher(
        connectivity,
        debounce: debounce,
      );

      final List<bool> emissions = <bool>[];
      final StreamSubscription<bool> sub = watcher.isOffline.listen(
        emissions.add,
      );

      controller.add(<ConnectivityResult>[ConnectivityResult.wifi]);
      await Future<void>.delayed(debounce * 3);
      controller.add(<ConnectivityResult>[ConnectivityResult.mobile]);
      await Future<void>.delayed(debounce * 3);
      controller.add(<ConnectivityResult>[ConnectivityResult.ethernet]);
      await Future<void>.delayed(debounce * 3);

      // Three online events collapse to one false emission via .distinct().
      expect(emissions, <bool>[false]);
      await sub.cancel();
    });

    test('currentIsOffline reads through to checkConnectivity', () async {
      when(
        () => connectivity.checkConnectivity(),
      ).thenAnswer((_) async => <ConnectivityResult>[ConnectivityResult.none]);
      final ConnectivityWatcher watcher = ConnectivityWatcher(connectivity);
      expect(await watcher.currentIsOffline(), isTrue);

      when(
        () => connectivity.checkConnectivity(),
      ).thenAnswer((_) async => <ConnectivityResult>[ConnectivityResult.wifi]);
      expect(await watcher.currentIsOffline(), isFalse);
    });

    test('treats an empty results list as offline (defensive guard)', () async {
      final ConnectivityWatcher watcher = ConnectivityWatcher(
        connectivity,
        debounce: const Duration(milliseconds: 5),
      );

      final Future<bool> first = watcher.isOffline.first;
      controller.add(<ConnectivityResult>[]);

      expect(await first, isTrue);
    });
  });
}
