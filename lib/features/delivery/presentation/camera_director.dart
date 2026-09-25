import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../core/config/app_constants.dart';
import '../../../core/maps/geo_bounds.dart';
import '../../../core/theme/app_motion.dart';

/// Owns the active-delivery map's camera autopilot.
///
/// 1. **Auto-fit suppression after a manual pan (R12.6).** [onUserPan]
///    stamps a timestamp; [shouldAutoFit] returns `false` for the
///    next [AppConstants.manualPanSuppressionWindow] (6 s).
///
/// 2. **Soft auto-fit (R12.7).** [maybeFitBounds] animates only when
///    [shouldAutoFit] returns `true`. It also tracks whether the
///    current route phase has already been fitted so we don't
///    re-fight the rider after the initial frame.
///
/// 3. **Phase-aware re-fit.** When the rider's `AssignmentStatus`
///    flips (`ACCEPTED` → `IN_TRANSIT`) the map controller calls
///    [resetPhaseFit] so the next [maybeFitBounds] forces a fresh
///    bounds animation.
class CameraDirector {
  CameraDirector({
    Duration suppressionWindow = AppConstants.manualPanSuppressionWindow,
    Duration animationDuration = AppMotion.slow,
  }) : _suppressionWindow = suppressionWindow,
       _animationDuration = animationDuration;

  final Duration _suppressionWindow;

  // ignore: unused_field
  final Duration _animationDuration;

  DateTime? _lastUserPanAt;
  bool _hasFittedForPhase = false;

  /// Latest pan timestamp recorded by [onUserPan]. Exposed for tests.
  DateTime? get lastUserPanAt => _lastUserPanAt;

  /// True iff the active route phase has been fitted at least once.
  bool get hasFittedForPhase => _hasFittedForPhase;

  /// Camera animation duration used by [maybeFitBounds] / [recenter].
  Duration get animationDuration => _animationDuration;

  /// Records a manual pan now. The suppression window starts from
  /// this moment (R12.6).
  void onUserPan() {
    _lastUserPanAt = DateTime.now();
  }

  /// Records a manual pan at an explicit instant. Used by tests so
  /// they don't need to clock-skew via [DateTime.now].
  void onUserPanAt(DateTime now) {
    _lastUserPanAt = now;
  }

  /// Whether the map is currently free to auto-fit at [now]. Returns
  /// `false` while inside the manual-pan suppression window.
  bool shouldAutoFit(DateTime now) {
    final DateTime? last = _lastUserPanAt;
    if (last == null) return true;
    return now.difference(last) >= _suppressionWindow;
  }

  /// Resets the phase-fit flag so the next [maybeFitBounds] performs
  /// a fresh bounds animation. Called by the map controller when the
  /// active route phase switches (`ACCEPTED` → `IN_TRANSIT`).
  void resetPhaseFit() {
    _hasFittedForPhase = false;
    _lastUserPanAt = null;
  }

  /// Soft auto-fit. Animates [controller] to fit [bounds] when
  /// [shouldAutoFit] returns `true`; otherwise returns immediately
  /// without touching the camera (R12.7).
  Future<void> maybeFitBounds({
    required MapController controller,
    required GeoBounds bounds,
    required DateTime now,
    double padding = _defaultPadding,
  }) async {
    if (!shouldAutoFit(now)) return;
    _hasFittedForPhase = true;
    controller.fitCamera(
      CameraFit.bounds(
        bounds: bounds.toLatLngBounds(),
        padding: EdgeInsets.all(padding),
      ),
    );
  }

  /// Hard recenter (R12.7). Always animates to [bounds], ignoring
  /// the suppression window — the rider has explicitly tapped the
  /// recenter button so we honour the request immediately.
  Future<void> recenter({
    required MapController controller,
    required GeoBounds bounds,
    double padding = _defaultPadding,
  }) async {
    _lastUserPanAt = null;
    _hasFittedForPhase = true;
    controller.fitCamera(
      CameraFit.bounds(
        bounds: bounds.toLatLngBounds(),
        padding: EdgeInsets.all(padding),
      ),
    );
  }

  /// Default padding (logical pixels) used when fitting bounds.
  static const double _defaultPadding = 80;
}
