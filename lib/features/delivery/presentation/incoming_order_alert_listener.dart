import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/alerts/alert_sound_player.dart';
import '../../../core/alerts/alert_vibration_player.dart';
import '../../../core/providers.dart';
import '../application/incoming_order_alert_decision.dart';
import '../application/offers_controller.dart';

/// Mounted once, at the app root (see `main.dart`'s `MaterialApp.router`
/// `builder`), so the incoming-order alarm rings regardless of which
/// screen the rider is currently looking at — not just while `HomeScreen`
/// happens to be the visible route.
///
/// [OffersController] is already the single, real-time source of truth
/// for "is there an offer I haven't acted on yet" (populated by
/// `DeliverySocketController` off the `order:assigned` / `order:expired` /
/// `order:status` Socket.IO events, and reconciled against
/// `GET /delivery/orders` on every reconnect/app-resume — see that
/// controller's own doc comment). This widget adds no new real-time
/// plumbing of its own; it only turns "an offer just became pending" /
/// "an offer just stopped being pending" into "start/stop the alarm",
/// via the pure [shouldPlayIncomingOrderAlert] decision so the exact
/// same rule can be unit-tested without a real audio/vibration platform.
///
/// The alarm stops itself in real time for every way an offer can stop
/// being pending — the rider accepts it (status moves to `accepted`),
/// the rider declines it (removed), it expires (removed), an admin
/// cancels it (removed), or another process takes it first (removed with
/// `ORDER_NOT_AVAILABLE` — see [OffersController.acceptOffer]'s 409
/// handling) — because all of those, without exception, go through
/// [OffersController]'s own state before anything else in the app
/// reacts, so this listener never has to special-case any one of them.
class IncomingOrderAlertListener extends ConsumerStatefulWidget {
  /// Wraps [child] (the routed app) so this stays mounted app-wide.
  const IncomingOrderAlertListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingOrderAlertListener> createState() =>
      _IncomingOrderAlertListenerState();
}

class _IncomingOrderAlertListenerState
    extends ConsumerState<IncomingOrderAlertListener> {
  bool _alerting = false;

  // Captured once, in [initState] — a Provider (not a ChangeNotifierProvider)
  // hands back the same instance for its whole lifetime, and reading it via
  // a field instead of `ref.read` again later means [dispose] never has to
  // touch `ref` after this widget has started unmounting, which Riverpod 3
  // treats as an error ("using ref when a widget is about to or has been
  // unmounted is unsafe").
  late final AlertSoundPlayer _sound;
  late final AlertVibrationPlayer _vibration;

  @override
  void initState() {
    super.initState();
    _sound = ref.read(alertSoundPlayerProvider);
    _vibration = ref.read(alertVibrationPlayerProvider);
    // Sync once against whatever state the controller already holds —
    // covers a hot-restart, or an offer that was reconciled from
    // GET /delivery/orders before this widget attached its listener.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync(ref.read<OffersController>(offersControllerProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    // `ref.listen` (not `ref.watch`): this widget wraps the entire routed
    // app, so it must never itself rebuild on every OffersController
    // change (accept/reject also toggle a transient "busy" flag via
    // notifyListeners, which would otherwise rebuild the whole app tree
    // on every keystroke-equivalent of that network call). A side-effect
    // subscription is exactly what `ref.listen` is for.
    ref.listen<OffersController>(offersControllerProvider, (
      OffersController? previous,
      OffersController next,
    ) {
      _sync(next);
    });
    return widget.child;
  }

  void _sync(OffersController controller) {
    final bool shouldPlay = shouldPlayIncomingOrderAlert(
      offers: controller.offers,
      hasActiveDelivery: controller.hasActiveDelivery,
    );
    if (shouldPlay == _alerting) return;
    _alerting = shouldPlay;
    if (shouldPlay) {
      unawaited(_sound.playLoop());
      unawaited(_vibration.startLoop());
    } else {
      unawaited(_sound.stop());
      unawaited(_vibration.stop());
    }
  }

  @override
  void dispose() {
    // Best-effort: stop whatever is ringing rather than leave it looping
    // past this widget's own lifetime (it never actually gets disposed in
    // production — it wraps the whole app — but tests mount/unmount it).
    if (_alerting) {
      unawaited(_sound.stop());
      unawaited(_vibration.stop());
    }
    super.dispose();
  }
}
