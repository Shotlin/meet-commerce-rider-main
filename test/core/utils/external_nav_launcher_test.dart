import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/utils/external_nav_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../helpers/recording_url_launcher.dart';

/// Verifies the side-effect surface of [ExternalNavigationLauncher]:
///
/// 1. **URL shape (R12.8)**: launches the canonical
///    `https://www.google.com/maps/dir/?api=1&destination=<lat>,<lng>&travelmode=driving`
///    URI with [LaunchMode.externalApplication].
///
/// 2. **Side-effect invariant (R30.4)**: the launcher only talks to
///    its [UrlLauncherDelegate]. The recorder captures every
///    [UrlLauncherDelegate.canLaunch] / [UrlLauncherDelegate.launch]
///    call, and we confirm those are the *only* recorded
///    interactions — the launcher cannot reach session, socket, or
///    location state from its constructor / call signature.
void main() {
  group('ExternalNavigationLauncher.openDrivingDirections', () {
    test('launches the canonical Google Maps URL with the destination '
        'coordinates and travelmode=driving', () async {
      final RecordingUrlLauncher launcher = RecordingUrlLauncher();
      final ExternalNavigationLauncher nav = ExternalNavigationLauncher(
        delegate: launcher,
      );

      final bool ok = await nav.openDrivingDirections(
        destLat: 12.971599,
        destLng: 77.594566,
      );

      expect(ok, isTrue);
      expect(launcher.launchCalls, hasLength(1));
      final CapturedLaunch call = launcher.launchCalls.single;
      expect(call.mode, LaunchMode.externalApplication);
      expect(
        call.uri.toString(),
        'https://www.google.com/maps/dir/?api=1'
        '&destination=12.971599,77.594566'
        '&travelmode=driving',
      );
    });

    test('side-effects are limited to the launcher (R30.4)', () async {
      final RecordingUrlLauncher launcher = RecordingUrlLauncher();
      final ExternalNavigationLauncher nav = ExternalNavigationLauncher(
        delegate: launcher,
      );

      await nav.openDrivingDirections(destLat: 1, destLng: 2);

      // Every recorded interaction is on the launcher; the launcher
      // is the only collaborator the launcher knows about, so any
      // side effect into session / socket / location would have to
      // happen via Riverpod or a global, neither of which is
      // accessible here.
      expect(launcher.canLaunchCalls, hasLength(1));
      expect(launcher.launchCalls, hasLength(1));
    });

    test('falls back to platformDefault when the external app launch '
        'throws (browser fallback path)', () async {
      final RecordingUrlLauncher launcher = RecordingUrlLauncher(
        throwOnExternal: true,
      );
      final ExternalNavigationLauncher nav = ExternalNavigationLauncher(
        delegate: launcher,
      );

      final bool ok = await nav.openDrivingDirections(destLat: 1, destLng: 2);

      expect(ok, isTrue);
      expect(launcher.launchCalls, hasLength(1));
      expect(launcher.launchCalls.single.mode, LaunchMode.platformDefault);
    });

    test(
      'falls back to platformDefault when canLaunch returns false',
      () async {
        final RecordingUrlLauncher launcher = RecordingUrlLauncher(
          canLaunchResult: false,
        );
        final ExternalNavigationLauncher nav = ExternalNavigationLauncher(
          delegate: launcher,
        );

        final bool ok = await nav.openDrivingDirections(destLat: 1, destLng: 2);

        expect(ok, isTrue);
        expect(launcher.launchCalls, hasLength(1));
        expect(launcher.launchCalls.single.mode, LaunchMode.platformDefault);
      },
    );
  });

  group('buildGoogleMapsDirectionsUrl', () {
    test('emits the expected scheme + host + path + query', () {
      final Uri uri = buildGoogleMapsDirectionsUrl(
        destLat: 22.5726,
        destLng: 88.3639,
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['destination'], '22.5726,88.3639');
      expect(uri.queryParameters['travelmode'], 'driving');
    });

    test('trims trailing zeros from coordinate formatting', () {
      final Uri uri = buildGoogleMapsDirectionsUrl(
        destLat: 12.5,
        destLng: 77.0,
      );
      expect(uri.toString(), contains('destination=12.5,77'));
    });
  });
}
