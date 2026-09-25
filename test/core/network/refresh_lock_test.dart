import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/network/auth_interceptor.dart';

/// Unit tests for [RefreshLock].
///
/// These cover the structural half of Property 1 (mutual exclusion of
/// in-flight refreshes). The retry-exactly-once half is exercised in the
/// AuthInterceptor integration test next to it.
void main() {
  group('RefreshLock.run', () {
    test(
      'runs body exactly once when called multiple times concurrently',
      () async {
        final RefreshLock lock = RefreshLock();
        int calls = 0;
        final Completer<bool> gate = Completer<bool>();

        Future<bool> body() {
          calls++;
          return gate.future;
        }

        final Future<bool> a = lock.run(body);
        final Future<bool> b = lock.run(body);
        final Future<bool> c = lock.run(body);

        // While the body has not completed yet, all three calls share one
        // future and the body has only been invoked once.
        expect(calls, 1);
        expect(lock.inFlight, isTrue);
        expect(identical(a, b), isTrue);
        expect(identical(a, c), isTrue);

        gate.complete(true);
        final List<bool> results = await Future.wait<bool>(<Future<bool>>[
          a,
          b,
          c,
        ]);

        expect(results, <bool>[true, true, true]);
        expect(calls, 1);
        expect(lock.inFlight, isFalse);
      },
    );

    test('a fresh call after completion runs the body again', () async {
      final RefreshLock lock = RefreshLock();
      int calls = 0;
      Future<bool> body() async {
        calls++;
        return true;
      }

      await lock.run(body);
      expect(calls, 1);
      await lock.run(body);
      expect(calls, 2);
    });

    test('lock releases even when the body throws', () async {
      final RefreshLock lock = RefreshLock();
      Future<bool> failing() async => throw StateError('boom');

      await expectLater(lock.run(failing), throwsStateError);
      expect(lock.inFlight, isFalse);

      // A subsequent call still runs the body.
      int calls = 0;
      await lock.run(() async {
        calls++;
        return true;
      });
      expect(calls, 1);
    });

    test('returns false when the body returns false', () async {
      final RefreshLock lock = RefreshLock();
      expect(await lock.run(() async => false), isFalse);
    });
  });
}
