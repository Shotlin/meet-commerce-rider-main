import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/notifications/notification_service.dart';
import 'package:meet_commerce_rider_main/firebase_options.dart';

/// Guards the Firebase configuration contract.
///
/// Android is registered in the `freshcuts-slin` project. iOS has no
/// GoogleService-Info.plist yet, so its options are deliberately invalid
/// placeholders; calling `Firebase.initializeApp` with them throws a native
/// NSException (FIRInstallations) outside Dart's ability to catch it. These
/// tests lock the guard so that regression can never come back silently.
void main() {
  test('Android uses the real freshcuts-slin project', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(DefaultFirebaseOptions.isConfigured, isTrue);
    expect(DefaultFirebaseOptions.android.projectId, 'freshcuts-slin');
    expect(
      DefaultFirebaseOptions.android.appId,
      '1:493517915093:android:eab57e958d836c795af35c',
    );
  });

  group('iOS (unconfigured)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('options are placeholders, not a real project', () {
      expect(DefaultFirebaseOptions.isConfigured, isFalse);
      expect(DefaultFirebaseOptions.ios.apiKey, contains('not-configured'));
      expect(DefaultFirebaseOptions.ios.appId, startsWith('1:000000000000'));
    });

    test('NotificationService.initialize() never touches the native Firebase '
        'SDK while unconfigured', () async {
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
