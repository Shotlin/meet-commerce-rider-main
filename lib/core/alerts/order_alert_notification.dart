import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/notification_service.dart';

/// Thin, injectable wrapper around `NotificationService`'s incoming-order
/// system notification — exists purely so `IncomingOrderAlertListener` can
/// depend on a small interface (like `AlertSoundPlayer`/
/// `AlertVibrationPlayer`) instead of reaching into the `NotificationService`
/// singleton directly, keeping it consistent with the other two alert
/// outputs and swappable for a fake in widget tests.
abstract class OrderAlertNotifier {
  Future<void> show({required String title, required String body});
  Future<void> cancel();
}

class NotificationServiceOrderAlertNotifier implements OrderAlertNotifier {
  const NotificationServiceOrderAlertNotifier();

  @override
  Future<void> show({required String title, required String body}) =>
      NotificationService.instance.showOrderAlertNotification(
        title: title,
        body: body,
      );

  @override
  Future<void> cancel() => NotificationService.instance.cancelOrderAlertNotification();
}

final Provider<OrderAlertNotifier> orderAlertNotifierProvider =
    Provider<OrderAlertNotifier>(
      (Ref ref) => const NotificationServiceOrderAlertNotifier(),
    );
