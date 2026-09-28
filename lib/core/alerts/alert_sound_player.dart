import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loops the incoming-order alert sound (like a ride-hailing driver app's
/// "new job" alert) until explicitly stopped — a single short chime is easy
/// to miss when the phone is in a pocket or on a bike mount; a loop keeps
/// ringing until the rider actually accepts, declines, or the offer is
/// taken by another process (see `IncomingOrderAlertListener`).
class AlertSoundPlayer {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  /// Whether the loop is currently active. Exposed for tests only — the
  /// listener tracks its own "should be playing" state independently so
  /// production code never needs to poll this.
  bool get isPlaying => _playing;

  Future<void> playLoop() async {
    if (_playing) return;
    _playing = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      // Ring at full volume regardless of whatever media volume the
      // rider last used for something else — a missed order offer is
      // costlier than a startlingly loud alert.
      await _player.setVolume(1.0);
      await _player.play(AssetSource('sounds/new_order_alert.mp3'));
    } catch (_) {
      // A missing/undecodable asset or a platform audio-session failure
      // must never crash the alert itself — the offer sheet still shows.
      _playing = false;
    }
  }

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {
      // Ignore — nothing meaningful to recover from a stop() failure.
    }
  }

  void dispose() {
    unawaited(_player.dispose());
  }
}

final Provider<AlertSoundPlayer> alertSoundPlayerProvider =
    Provider<AlertSoundPlayer>((Ref ref) {
      final AlertSoundPlayer player = AlertSoundPlayer();
      ref.onDispose(player.dispose);
      return player;
    });
