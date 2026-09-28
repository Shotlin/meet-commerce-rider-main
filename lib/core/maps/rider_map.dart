import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../features/delivery/domain/delivery_address.dart';
import 'geo_point.dart';
import 'marker_icon_renderer.dart';
import 'rider_maps_service.dart';

/// What to draw on the rider map. MapLibre-agnostic on purpose — the
/// delivery controllers produce these, [RiderMap] applies them to the
/// native style (Big Phase 12 architecture decision).
@immutable
class RiderMarkerSpec {
  /// Constructs a marker spec.
  const RiderMarkerSpec({
    required this.id,
    required this.position,
    required this.color,
    this.radiusDp = 9,
    this.strokeColor = '#FFFFFF',
    this.strokeWidthDp = 2,
    this.kind = RiderMarkerKind.dot,
    this.headingDegrees,
  });

  /// Stable id — re-applying updates the same native circle instead of
  /// stacking a new one.
  final String id;
  final GeoPoint position;

  /// Fill colour as a `#RRGGBB` string (MapLibre style format).
  final String color;
  final double radiusDp;
  final String strokeColor;
  final double strokeWidthDp;

  /// Rider / store / customer render as an icon badge; [RiderMarkerKind.dot]
  /// keeps the plain coloured circle.
  final RiderMarkerKind kind;

  /// Real-world travel direction (degrees clockwise from north) for a
  /// [RiderMarkerKind.riderHeading] marker; null for everything else.
  final double? headingDegrees;
}

/// The route polyline drawn under the markers.
@immutable
class RiderRouteSpec {
  /// Constructs a route spec.
  const RiderRouteSpec({required this.points, this.color = '#2563EB'});

  final List<GeoPoint> points;

  /// `#RRGGBB` string.
  final String color;
}

/// Standard markers for a delivery map phase, from the order's own
/// addresses. Null entries are skipped by [RiderMap].
RiderMarkerSpec riderMarkerFor({
  required String id,
  required DeliveryAddress address,
  required String color,
  double radiusDp = 9,
}) {
  final double? lat = address.lat;
  final double? lng = address.lng;
  if (lat == null || lng == null) {
    return RiderMarkerSpec(
      id: id,
      position: const GeoPoint(0, 0),
      color: color,
      radiusDp: radiusDp,
    );
  }
  return RiderMarkerSpec(
    id: id,
    position: GeoPoint(lat, lng),
    color: color,
    radiusDp: radiusDp,
  );
}

/// How the camera is being driven.
enum RiderCameraMode {
  /// Glued to the rider at navigation zoom, turning with their heading.
  follow,

  /// Framing the rider and the whole remaining route.
  overview,

  /// The rider panned / zoomed / rotated by hand — the camera stays put until
  /// they pick [follow] or [overview] again.
  free,
}

/// Interactive rider map rendering the backend-proxied Ola vector style
/// through MapLibre native on both platforms (Big Phase 12).
///
/// Responsibilities:
/// - loads the style once via [RiderMapsService]; when Ola Maps isn't
///   configured dashboard-side it renders [fallbackBuilder] instead of
///   pretending (no-placeholder rule);
/// - applies [markers] / [route] as native symbols / a road polyline,
///   serialised and diffed by stable ids so GPS ticks update instead of
///   stack (and an old route can never be left behind);
/// - two distinct camera behaviours: **overview** (fit the rider + the
///   remaining route, once per [overviewToken]) and **follow** (close,
///   heading-aware navigation view of [riderPosition]).
class RiderMap extends StatefulWidget {
  /// Constructs the rider map.
  const RiderMap({
    required this.availability,
    required this.markers,
    this.route,
    this.riderPosition,
    this.riderHeading,
    this.fitPoints = const <GeoPoint>[],
    this.overviewToken = 0,
    this.pitched = false,
    this.initialZoom = 15,
    this.followZoom = 16.5,
    this.onCameraModeChanged,
    this.onStyleReady,
    this.onReady,
    this.fallbackBuilder,
    super.key,
  });

  final Future<OlaMapsAvailability> availability;
  final List<RiderMarkerSpec> markers;
  final RiderRouteSpec? route;

  /// The rider's latest valid fix — what follow mode tracks.
  final GeoPoint? riderPosition;

  /// Reliable travel heading in degrees (null = unknown).
  final double? riderHeading;

  /// Points overview mode should frame.
  final List<GeoPoint> fitPoints;

  /// Changes whenever the whole journey should be re-framed (new route for a
  /// new destination). Overview mode is entered and fitted on each change.
  final int overviewToken;

  final bool pitched;
  final double initialZoom;

  /// Zoom used when the rider taps recenter — a close navigation level.
  final double followZoom;

  final ValueChanged<RiderCameraMode>? onCameraModeChanged;
  final VoidCallback? onStyleReady;

  /// Called once the style is loaded and the imperative handle works.
  final ValueChanged<RiderMapHandle>? onReady;
  final WidgetBuilder? fallbackBuilder;

  @override
  State<RiderMap> createState() => _RiderMapState();
}

/// Handle the parent screen keeps for imperative camera actions.
class RiderMapHandle {
  RiderMapHandle({
    required VoidCallback recenter,
    required VoidCallback overview,
  }) : _recenter = recenter,
       _overview = overview;

  final VoidCallback _recenter;
  final VoidCallback _overview;

  /// Jumps to the rider's latest GPS position at navigation zoom (with the
  /// map turned to their heading when known) and resumes follow mode.
  void recenter() => _recenter();

  /// Frames the rider and the remaining route (overview mode).
  void overview() => _overview();
}

class _RiderMapState extends State<RiderMap> {
  ml.MapLibreMapController? _controller;
  bool _styleLoaded = false;

  RiderCameraMode _mode = RiderCameraMode.follow;
  int _appliedOverviewToken = 0;
  GeoPoint? _lastFollowed;
  DateTime _lastFollowAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Camera moves we start ourselves finish with an idle event too; anything
  /// idle outside this window was the rider's own gesture.
  DateTime _programmaticUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // `_apply` is single-flight: annotation adds are async and two overlapping
  // runs would each add "the" route line before either handle came back.
  bool _applying = false;
  bool _applyAgain = false;

  /// Trailing follow update: a GPS tick that lands inside the follow
  /// throttle is replayed once the window ends, so the camera never rests on
  /// a stale fix.
  Timer? _followTrailing;

  /// Native objects by logical id, captured from addCircle/addLine —
  /// MapLibre assigns ids at add time, so updates/removals must go
  /// through the returned handles.
  final Map<String, ml.Circle> _nativeCircles = <String, ml.Circle>{};
  final Map<String, ml.Symbol> _nativeSymbols = <String, ml.Symbol>{};

  /// Marker images registered in the CURRENT style (a style reload drops
  /// them, so this is cleared in onStyleLoadedCallback).
  final Set<RiderMarkerKind> _registeredKinds = <RiderMarkerKind>{};
  ml.Line? _nativeRoute;
  ml.Line? _nativeRouteCasing;

  static const Duration _followTick = Duration(milliseconds: 900);
  static const Duration _followAnimation = Duration(milliseconds: 700);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OlaMapsAvailability>(
      future: widget.availability,
      builder: (BuildContext context, AsyncSnapshot<OlaMapsAvailability> snap) {
        final OlaMapsAvailability? availability = snap.data;
        if (availability == null) {
          return const ColoredBox(color: Color(0xFFEAECEF));
        }
        if (!availability.configured || availability.styleUrl == null) {
          return widget.fallbackBuilder?.call(context) ??
              const _MapUnavailableFallback();
        }
        return ml.MapLibreMap(
          styleString: availability.styleUrl!,
          initialCameraPosition: ml.CameraPosition(
            target: _toLatLng(
              widget.riderPosition ??
                  (widget.fitPoints.isNotEmpty
                      ? widget.fitPoints.first
                      : const GeoPoint(22.5726, 88.3639)),
            ),
            zoom: widget.initialZoom,
            tilt: widget.pitched ? 45 : 0,
          ),
          trackCameraPosition: true,
          compassEnabled: true,
          rotateGesturesEnabled: true,
          myLocationEnabled: false,
          onMapCreated: (ml.MapLibreMapController controller) {
            _controller = controller;
          },
          onStyleLoadedCallback: () {
            _styleLoaded = true;
            _registeredKinds.clear();
            _nativeCircles.clear();
            _nativeSymbols.clear();
            _nativeRoute = null;
            _nativeRouteCasing = null;
            // The style load itself settles the camera; don't read that as
            // the rider dragging the map.
            _markProgrammatic(const Duration(seconds: 2));
            widget.onStyleReady?.call();
            widget.onReady?.call(
              RiderMapHandle(
                recenter: () => unawaited(_enterFollow(forceZoom: true)),
                overview: () => unawaited(_enterOverview()),
              ),
            );
            unawaited(_allowMarkerOverlap());
            unawaited(_apply());
          },
          onCameraIdle: _onCameraIdle,
        );
      },
    );
  }

  @override
  void didUpdateWidget(RiderMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_apply());
  }

  @override
  void dispose() {
    _followTrailing?.cancel();
    super.dispose();
  }

  void _markProgrammatic(Duration d) {
    final DateTime until = DateTime.now().add(d);
    if (until.isAfter(_programmaticUntil)) _programmaticUntil = until;
  }

  void _setMode(RiderCameraMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    widget.onCameraModeChanged?.call(mode);
  }

  void _onCameraIdle() {
    if (!mounted) return;
    if (DateTime.now().isBefore(_programmaticUntil)) {
      // Our own camera move finished — the map may have rotated, so the
      // heading pointer's on-screen angle needs refreshing.
      unawaited(_apply());
      return;
    }
    // A rider drag / pinch / rotate wins over every programmatic camera
    // move until they recenter or ask for the overview.
    _setMode(RiderCameraMode.free);
    unawaited(_apply());
  }

  /// Badges must never be hidden by label collision / each other.
  Future<void> _allowMarkerOverlap() async {
    final ml.MapLibreMapController? controller = _controller;
    if (controller == null) return;
    await controller.setSymbolIconAllowOverlap(true);
    await controller.setSymbolIconIgnorePlacement(true);
  }

  Future<void> _apply() async {
    if (_controller == null || !_styleLoaded) return;
    if (_applying) {
      _applyAgain = true;
      return;
    }
    _applying = true;
    try {
      do {
        _applyAgain = false;
        await _applyAnnotations();
        await _applyCamera();
      } while (_applyAgain && mounted);
    } catch (_) {
      // A platform hiccup (style reloading mid-update) must not take the
      // screen down; the next widget update re-applies from scratch.
    } finally {
      _applying = false;
    }
  }

  Future<void> _applyAnnotations() async {
    final ml.MapLibreMapController? controller = _controller;
    if (controller == null || !_styleLoaded) return;

    // Route polyline: a white casing under the blue line, added before the
    // markers so markers render on top. Always the road geometry handed in,
    // replaced in place — never accumulated.
    final RiderRouteSpec? route = widget.route;
    if (route != null && route.points.length >= 2) {
      final List<ml.LatLng> line = route.points.map(_toLatLng).toList();
      final ml.LineOptions casing = ml.LineOptions(
        geometry: line,
        lineColor: '#FFFFFF',
        lineWidth: 9.0,
        lineJoin: 'round',
        lineOpacity: 0.95,
      );
      final ml.LineOptions main = ml.LineOptions(
        geometry: line,
        lineColor: route.color,
        lineWidth: 5.5,
        lineJoin: 'round',
      );
      if (_nativeRouteCasing != null) {
        await controller.updateLine(_nativeRouteCasing!, casing);
      } else {
        _nativeRouteCasing = await controller.addLine(casing);
      }
      if (_nativeRoute != null) {
        await controller.updateLine(_nativeRoute!, main);
      } else {
        _nativeRoute = await controller.addLine(main);
      }
    } else {
      if (_nativeRoute != null) {
        await controller.removeLine(_nativeRoute!);
        _nativeRoute = null;
      }
      if (_nativeRouteCasing != null) {
        await controller.removeLine(_nativeRouteCasing!);
        _nativeRouteCasing = null;
      }
    }

    // Markers, diffed by stable id. Rider / store / customer are icon
    // symbols; anything else stays a plain circle.
    final Map<String, RiderMarkerSpec> wanted = <String, RiderMarkerSpec>{
      for (final RiderMarkerSpec m in widget.markers) m.id: m,
    };
    for (final String id in _nativeCircles.keys.toSet()) {
      final RiderMarkerSpec? spec = wanted[id];
      if (spec == null || spec.kind != RiderMarkerKind.dot) {
        await controller.removeCircle(_nativeCircles[id]!);
        _nativeCircles.remove(id);
      }
    }
    for (final String id in _nativeSymbols.keys.toSet()) {
      final RiderMarkerSpec? spec = wanted[id];
      if (spec == null || spec.kind == RiderMarkerKind.dot) {
        await controller.removeSymbol(_nativeSymbols[id]!);
        _nativeSymbols.remove(id);
      }
    }
    for (final MapEntry<String, RiderMarkerSpec> entry in wanted.entries) {
      final RiderMarkerSpec spec = entry.value;
      if (spec.kind == RiderMarkerKind.dot) {
        final ml.CircleOptions options = _circleOptions(spec);
        final ml.Circle? native = _nativeCircles[entry.key];
        if (native != null) {
          await controller.updateCircle(native, options);
        } else {
          _nativeCircles[entry.key] = await controller.addCircle(options);
        }
        continue;
      }
      await _ensureMarkerImage(controller, spec.kind);
      final ml.SymbolOptions options = _symbolOptions(spec);
      final ml.Symbol? native = _nativeSymbols[entry.key];
      if (native != null) {
        await controller.updateSymbol(native, options);
      } else {
        _nativeSymbols[entry.key] = await controller.addSymbol(options);
      }
    }
  }

  /// Camera policy — overview is a one-shot fit per [RiderMap.overviewToken];
  /// follow tracks the rider; free never moves on its own.
  Future<void> _applyCamera() async {
    if (widget.overviewToken != _appliedOverviewToken) {
      // A new journey leg (first route for a destination) — frame it all.
      if (widget.fitPoints.length >= 2) {
        _appliedOverviewToken = widget.overviewToken;
        await _enterOverview();
        return;
      }
    }
    if (_mode == RiderCameraMode.follow) {
      await _followRider();
    }
  }

  Future<void> _enterOverview() async {
    final ml.MapLibreMapController? controller = _controller;
    if (controller == null || !_styleLoaded) return;
    final List<GeoPoint> points = widget.fitPoints;
    if (points.length < 2) {
      // Nothing to frame yet — at least show the rider.
      await _enterFollow(forceZoom: false);
      return;
    }
    _setMode(RiderCameraMode.overview);
    _markProgrammatic(const Duration(milliseconds: 900));
    await controller.moveCamera(
      ml.CameraUpdate.newLatLngBounds(
        _paddedBounds(points.map(_toLatLng).toList()),
        left: 56,
        top: 128, // clears the top status/ETA bar
        right: 56,
        bottom: 72,
      ),
    );
    if (!mounted) return;
    // Overview is north-up, so the heading pointer is aimed absolutely.
    _applyAgainSoon();
  }

  /// Recenter: rider at the centre, navigation zoom, map turned to the
  /// travel direction when we have one.
  Future<void> _enterFollow({required bool forceZoom}) async {
    _setMode(RiderCameraMode.follow);
    _lastFollowAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastFollowed = null;
    await _followRider(forceZoom: forceZoom);
  }

  Future<void> _followRider({bool forceZoom = false}) async {
    final ml.MapLibreMapController? controller = _controller;
    final GeoPoint? rider = widget.riderPosition;
    if (controller == null || !_styleLoaded || rider == null) return;

    final DateTime now = DateTime.now();
    final bool moved = _lastFollowed == null || _lastFollowed != rider;
    if (!moved && !forceZoom) return;
    final Duration sinceLast = now.difference(_lastFollowAt);
    if (!forceZoom && sinceLast < _followTick) {
      _followTrailing?.cancel();
      _followTrailing = Timer(_followTick - sinceLast, () {
        if (mounted && _mode == RiderCameraMode.follow) unawaited(_apply());
      });
      return;
    }
    _lastFollowAt = now;
    _lastFollowed = rider;

    final ml.CameraPosition? current = controller.cameraPosition;
    // First follow (or explicit recenter) sets the navigation zoom; after
    // that a rider-chosen zoom would have dropped us to free mode, so the
    // current zoom is simply preserved between ticks.
    final double zoom = (forceZoom || current == null)
        ? widget.followZoom
        : current.zoom;
    final double bearing = widget.riderHeading ?? current?.bearing ?? 0;

    _markProgrammatic(_followAnimation + const Duration(milliseconds: 500));
    await controller.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: _toLatLng(rider),
          zoom: zoom,
          bearing: bearing,
          tilt: widget.pitched ? 45 : 0,
        ),
      ),
      duration: _followAnimation,
    );
    if (!mounted) return;
    _applyAgainSoon();
  }

  void _applyAgainSoon() {
    // Refresh the heading pointer against the new map bearing.
    if (_applying) {
      _applyAgain = true;
    } else {
      unawaited(_apply());
    }
  }

  Future<void> _ensureMarkerImage(
    ml.MapLibreMapController controller,
    RiderMarkerKind kind,
  ) async {
    if (_registeredKinds.contains(kind)) return;
    final RiderMarkerStyle? style = RiderMarkerStyle.of(kind);
    if (style == null) return;
    // Mark first so concurrent _apply() calls don't render the same image
    // twice; undo if the render/registration fails so it retries.
    _registeredKinds.add(kind);
    try {
      await controller.addImage(
        riderMarkerImageName(kind),
        await renderRiderMarkerIcon(style),
      );
    } catch (_) {
      _registeredKinds.remove(kind);
      rethrow;
    }
  }

  /// The badge PNG is ~130px. Android treats a decoded bitmap at device
  /// density (≈44dp on a 3x phone at size 1.0); iOS reads it at scale 1, so
  /// it needs shrinking there.
  static double get _symbolScale =>
      defaultTargetPlatform == TargetPlatform.iOS ? 0.34 : 1.0;

  ml.SymbolOptions _symbolOptions(RiderMarkerSpec spec) {
    // Symbols rotate relative to the screen, so the pointer's on-screen
    // angle is the real heading minus however far the map itself is turned.
    final double? heading = spec.headingDegrees;
    final double mapBearing = _controller?.cameraPosition?.bearing ?? 0;
    final double? rotation = heading == null
        ? null
        : (((heading - mapBearing) % 360) + 360) % 360;
    return ml.SymbolOptions(
      geometry: _toLatLng(spec.position),
      iconImage: riderMarkerImageName(spec.kind),
      iconSize: _symbolScale,
      iconAnchor: 'center',
      iconRotate: rotation ?? 0,
      // The rider badge always draws on top of store / customer.
      zIndex: spec.kind == RiderMarkerKind.rider ||
              spec.kind == RiderMarkerKind.riderHeading
          ? 3
          : 1,
    );
  }

  ml.CircleOptions _circleOptions(RiderMarkerSpec spec) {
    return ml.CircleOptions(
      geometry: _toLatLng(spec.position),
      circleColor: spec.color,
      circleRadius: spec.radiusDp,
      circleStrokeColor: spec.strokeColor,
      circleStrokeWidth: spec.strokeWidthDp,
      circleOpacity: 1,
    );
  }

  static ml.LatLng _toLatLng(GeoPoint p) => ml.LatLng(p.latitude, p.longitude);

  /// Bounds around [points], never tighter than ~300 m so a rider standing at
  /// the store doesn't get an absurd street-level zoom.
  static ml.LatLngBounds _paddedBounds(List<ml.LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final ml.LatLng p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    const double minSpanDegrees = 0.0028;
    if (maxLat - minLat < minSpanDegrees) {
      final double mid = (maxLat + minLat) / 2;
      minLat = mid - minSpanDegrees / 2;
      maxLat = mid + minSpanDegrees / 2;
    }
    if (maxLng - minLng < minSpanDegrees) {
      final double mid = (maxLng + minLng) / 2;
      minLng = mid - minSpanDegrees / 2;
      maxLng = mid + minSpanDegrees / 2;
    }
    return ml.LatLngBounds(
      southwest: ml.LatLng(minLat, minLng),
      northeast: ml.LatLng(maxLat, maxLng),
    );
  }
}

/// Honest fallback when Ola Maps isn't configured dashboard-side — the
/// map surface says so instead of rendering a blank canvas.
class _MapUnavailableFallback extends StatelessWidget {
  const _MapUnavailableFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEAECEF),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.map_outlined,
                size: 40,
                color: Color(0xFF667085),
              ),
              const SizedBox(height: 12),
              Text(
                'Map unavailable',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Ola Maps is not configured for this environment yet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience: markers for the three operational roles from an order's
/// addresses, skipping the ones without coordinates.
List<RiderMarkerSpec> riderMarkersForOrder({
  required DeliveryAddress? store,
  required DeliveryAddress? customer,
  GeoPoint? rider,
  double? riderHeading,
}) {
  final List<RiderMarkerSpec> markers = <RiderMarkerSpec>[];
  if (rider != null) {
    markers.add(
      RiderMarkerSpec(
        id: 'rider',
        position: rider,
        color: '#101114',
        radiusDp: 8,
        kind: riderHeading == null
            ? RiderMarkerKind.rider
            : RiderMarkerKind.riderHeading,
        headingDegrees: riderHeading,
      ),
    );
  }
  if (store != null && store.lat != null && store.lng != null) {
    markers.add(
      RiderMarkerSpec(
        id: 'store',
        position: GeoPoint(store.lat!, store.lng!),
        color: '#E61F2C',
        radiusDp: 9,
        kind: RiderMarkerKind.store,
      ),
    );
  }
  if (customer != null && customer.lat != null && customer.lng != null) {
    markers.add(
      RiderMarkerSpec(
        id: 'customer',
        position: GeoPoint(customer.lat!, customer.lng!),
        color: '#2563EB',
        radiusDp: 9,
        kind: RiderMarkerKind.customer,
      ),
    );
  }
  return markers;
}
