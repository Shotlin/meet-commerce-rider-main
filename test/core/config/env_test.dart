import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/config/env.dart';
import 'package:meet_commerce_rider_main/core/config/flavor.dart';

/// Unit tests for the environment configuration value object.
///
/// Acceptance for Task 0.2:
/// - `Env.current` defaults to `AppFlavor.dev` when no `--dart-define`
///   token is supplied (which is what `flutter test` does).
/// - All three flavors expose the same live backend URLs.
/// - `enableDevAffordances` is true only for [AppFlavor.dev].
void main() {
  group('Env.current', () {
    test('defaults to AppFlavor.dev when no dart-define is given', () {
      // `flutter test` does not pass --dart-define=FLAVOR=..., so the
      // build-time const inside Env defaults to "dev".
      expect(Env.current.flavor, AppFlavor.dev);
      expect(Env.current.enableDevAffordances, isTrue);
    });

    test('points at the Meet Commerce backend', () {
      // Default target for every flavor unless API_BASE_URL/SOCKET_BASE_URL
      // are overridden with --dart-define (see Env.forFlavor).
      expect(Env.current.apiBaseUrl, 'https://api.fc.opslin.com/api/v1');
      expect(Env.current.socketBaseUrl, 'https://api.fc.opslin.com');
    });
  });

  group('Env.forFlavor', () {
    test('all three flavors expose the same Meet Commerce backend URLs', () {
      const expectedApi = 'https://api.fc.opslin.com/api/v1';
      const expectedSocket = 'https://api.fc.opslin.com';

      for (final flavor in AppFlavor.values) {
        final env = Env.forFlavor(flavor);
        expect(
          env.apiBaseUrl,
          expectedApi,
          reason:
              'apiBaseUrl must be the Meet Commerce backend for '
              '${flavor.name}',
        );
        expect(
          env.socketBaseUrl,
          expectedSocket,
          reason:
              'socketBaseUrl must be the Meet Commerce backend for '
              '${flavor.name}',
        );
      }
    });

    test('never falls back to a decommissioned legacy host', () {
      for (final flavor in AppFlavor.values) {
        final env = Env.forFlavor(flavor);
        for (final String url in <String>[env.apiBaseUrl, env.socketBaseUrl]) {
          expect(url.contains('bakaloo'), isFalse);
          expect(url.contains('grolin'), isFalse);
          expect(Uri.parse(url).scheme, 'https');
        }
      }
    });

    test('enableDevAffordances is true only for AppFlavor.dev', () {
      expect(Env.forFlavor(AppFlavor.dev).enableDevAffordances, isTrue);
      expect(Env.forFlavor(AppFlavor.staging).enableDevAffordances, isFalse);
      expect(Env.forFlavor(AppFlavor.prod).enableDevAffordances, isFalse);
    });

    test('flavor field round-trips for every variant', () {
      for (final flavor in AppFlavor.values) {
        expect(Env.forFlavor(flavor).flavor, flavor);
      }
    });
  });

  group('AppFlavor.parse', () {
    test('accepts canonical lowercase tokens', () {
      expect(AppFlavor.parse('dev'), AppFlavor.dev);
      expect(AppFlavor.parse('staging'), AppFlavor.staging);
      expect(AppFlavor.parse('prod'), AppFlavor.prod);
    });

    test('accepts common aliases', () {
      expect(AppFlavor.parse('development'), AppFlavor.dev);
      expect(AppFlavor.parse('stage'), AppFlavor.staging);
      expect(AppFlavor.parse('qa'), AppFlavor.staging);
      expect(AppFlavor.parse('production'), AppFlavor.prod);
      expect(AppFlavor.parse('release'), AppFlavor.prod);
    });

    test('is case insensitive and tolerant of surrounding whitespace', () {
      expect(AppFlavor.parse(' DEV '), AppFlavor.dev);
      expect(AppFlavor.parse('Staging'), AppFlavor.staging);
      expect(AppFlavor.parse('PROD'), AppFlavor.prod);
    });

    test('treats the empty string as dev', () {
      expect(AppFlavor.parse(''), AppFlavor.dev);
    });

    test('throws ArgumentError for unknown tokens', () {
      expect(() => AppFlavor.parse('beta'), throwsArgumentError);
      expect(() => AppFlavor.parse('localhost'), throwsArgumentError);
    });

    test('helper getters reflect the active flavor', () {
      expect(AppFlavor.dev.isDev, isTrue);
      expect(AppFlavor.dev.isStaging, isFalse);
      expect(AppFlavor.dev.isProd, isFalse);

      expect(AppFlavor.staging.isDev, isFalse);
      expect(AppFlavor.staging.isStaging, isTrue);
      expect(AppFlavor.staging.isProd, isFalse);

      expect(AppFlavor.prod.isDev, isFalse);
      expect(AppFlavor.prod.isStaging, isFalse);
      expect(AppFlavor.prod.isProd, isTrue);
    });
  });
}
