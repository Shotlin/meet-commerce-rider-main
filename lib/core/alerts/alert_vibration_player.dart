import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

/// Loops a strong, unmissable vibration pattern alongside
/// [AlertSoundPlayer] for an incoming order — a phone on silent, in a
/// pocket, or on a bike mount still needs to physically buzz until the
/// rider notices, not just chime once.
///
/// Pattern: `[0, 800, 400, 800, 400, 800, 400, 800]` — no initial delay,
/// four 800 ms buzzes separated by 400 ms pauses, repeating from index 0
/// (the platform loops the whole pattern, not just the tail) until
/// [stop] is called. Falls back to nothing (never throws) on a device
/// with no vibrator or no custom-pattern support.
class AlertVibrationPlayer {
  static const List<int> _pattern = <int>[0, 800, 400, 800, 400, 800, 400, 800];

  bool _vibrating = false;

  /// Whether the loop is currently active. Exposed for tests only.
  bool get isVibrating => _vibrating;

  Future<void> startLoop() async {
    if (_vibrating) return;
    _vibrating = true;
    try {
      final bool hasVibrator = await Vibration.hasVibrator();
      if (!hasVibrator) {
        _vibrating = false;
        return;
      }
      await Vibration.vibrate(pattern: _pattern, repeat: 0);
    } catch (_) {
      // A missing platform channel or an unsupported device must never
      // crash the alert itself — the sound + sheet still work.
      _vibrating = false;
    }
  }

  Future<void> stop() async {
    if (!_vibrating) return;
    _vibrating = false;
    try {
      await Vibration.cancel();
    } catch (_) {
      // Ignore — nothing meaningful to recover from a cancel() failure.
    }
  }
}

final Provider<AlertVibrationPlayer> alertVibrationPlayerProvider =
    Provider<AlertVibrationPlayer>((Ref ref) => AlertVibrationPlayer());
