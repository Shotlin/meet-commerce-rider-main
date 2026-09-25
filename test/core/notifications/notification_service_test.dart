import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/notifications/notification_service.dart';
import 'package:meet_commerce_rider_main/firebase_options.dart';

/// Guards the unconfigured-Firebase contract.
///
/// The app id `com.meetcommerce.rider` has no registered Firebase project yet,
/// so `firebase_options.dart` holds deliberately invalid placeholder values.
/// Calling `Firebase.initializeApp` with them throws a native NSException
/// (FIRInstallations) on iOS *outside* Dart's ability to catch it — the process
/// dies before the first frame. These tests lock the guard so that regression
/// can never come back silently.
void main() {
  test('Firebase options are placeholders, not a real project', () {
    expect(
      DefaultFirebaseOptions.isConfigured,
      isFalse,
      reason: 'Flip this to true only with generated FlutterFire config',
    );
    expect(DefaultFirebaseOptions.android.apiKey, contains('not-configured'));
    expect(DefaultFirebaseOptions.ios.apiKey, contains('not-configured'));
    expect(DefaultFirebaseOptions.android.appId, startsWith('1:000000000000'));
    expect(DefaultFirebaseOptions.ios.appId, startsWith('1:000000000000'));
  });

  test('NotificationService.initialize() never touches the native Firebase SDK '
      'while unconfigured', () async {
    // Must complete (not throw) and leave Firebase untouched: touching it is
    // what crashes the process on iOS.
    await NotificationService.instance.initialize();

    expect(Firebase.apps, isEmpty);
    expect(NotificationService.instance.fcmToken, isNull);
  });

  test('initialize() is idempotent — repeat calls are no-ops', () async {
    await NotificationService.instance.initialize();
    await NotificationService.instance.initialize();

    expect(Firebase.apps, isEmpty);
    expect(NotificationService.instance.fcmToken, isNull);
  });

  group('registerFcmTokenWithBackend', () {
    test('skips an empty token', () async {
      int calls = 0;
      await registerFcmTokenWithBackend(
        token: '',
        onRegister: (String token, String platform) async => calls++,
      );
      expect(calls, 0);
    });

    test('forwards the token with the current platform id', () async {
      final List<(String, String)> calls = <(String, String)>[];
      await registerFcmTokenWithBackend(
        token: 'abc123',
        onRegister: (String token, String platform) async =>
            calls.add((token, platform)),
      );

      expect(calls, hasLength(1));
      expect(calls.single.$1, 'abc123');
      expect(calls.single.$2, anyOf('ios', 'android'));
    });

    test('swallows registration failures so sign-in never breaks', () async {
      await expectLater(
        registerFcmTokenWithBackend(
          token: 'abc123',
          onRegister: (String token, String platform) async =>
              throw StateError('backend down'),
        ),
        completes,
      );
    });
  });
}
