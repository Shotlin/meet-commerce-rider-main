import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/features/auth/application/session_controller.dart';

void main() {
  test('rider push tokens are labelled app=rider so customer campaigns never '
      'reach the rider app', () {
    final Map<String, dynamic> body = fcmRegistrationBody(
      'tok-123',
      platform: TargetPlatform.android,
    );
    expect(body, <String, dynamic>{
      'token': 'tok-123',
      'platform': 'android',
      'app': 'rider',
    });
  });

  test('reports the real platform for iOS devices', () {
    expect(
      fcmRegistrationBody('t', platform: TargetPlatform.iOS)['platform'],
      'ios',
    );
  });
}
