// Firebase configuration for the Freashcut Rider app.
//
// UNCONFIGURED BY DESIGN — see the explanation below. Regenerate this file
// with the FlutterFire CLI once the Meet Commerce Firebase project exists and
// has apps registered for the `com.meetcommerce.rider` Android/iOS ids.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  /// Whether a real Firebase project has been registered for this app id.
  ///
  /// False while the placeholder values below are in place. Push/analytics
  /// code paths must treat Firebase as unavailable in that state instead of
  /// reporting into somebody else's project.
  static const bool isConfigured = false;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Placeholder/dummy values — deliberately NOT another company's real
  // Firebase project. The Meet Commerce / FreshCuts ecosystem has no Firebase
  // project registered for this application id yet, and the app treats a
  // Firebase initialization failure as non-fatal
  // (see `NotificationService.initialize`), so these intentionally fail to
  // initialize rather than silently sending this product's push tokens and
  // analytics into an unrelated live project.
  //
  // Required external step before release: register Android (com.meetcommerce.rider,
  // com.meetcommerce.rider.dev, com.meetcommerce.rider.staging) and iOS
  // (com.meetcommerce.rider) apps in the Meet Commerce Firebase project, then
  // replace this file and android/app/google-services.json with the generated
  // configuration.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'dummy-not-configured',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'meet-commerce-dev-unconfigured',
    storageBucket: 'meet-commerce-dev-unconfigured.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'dummy-not-configured',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'meet-commerce-dev-unconfigured',
    storageBucket: 'meet-commerce-dev-unconfigured.firebasestorage.app',
    iosBundleId: 'com.meetcommerce.rider',
  );
}
