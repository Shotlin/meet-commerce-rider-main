import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../features/delivery/domain/delivery_address.dart';
import 'geo_point.dart';
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

/// Interactive rider map rendering the backend-proxied Ola vector style
/// through MapLibre native on both platforms (Big Phase 12).
///
/// Responsibilities:
/// - loads the style once via [RiderMapsService]; when Ola Maps isn't
///   configured dashboard-side it renders [fallbackBuilder] instead of
///   pretending (no-placeholder rule);
/// - applies [markers] / [route] as native circles / a polyline,
///   diffing by stable ids so GPS ticks update instead of stack;
/// - fits the camera to the visible geometry ([fitPoints]) and honors
///   [pitched] for the 3D tilt (MapLibre camera pitch — whether true
///   3D buildings appear depends on Ola's style layers; this widget
///   never claims more than the style renders).
class RiderMap extends StatefulWidget {
  /// Constructs the rider map.
  const RiderMap({
    required this.availability,
    required this.markers,
    this.route,
    this.followTarget,
    this.fitPoints = const <GeoPoint>[],
    this.pitched = false,
    this.initialZoom = 14,
    this.onUserPan,
    this.onStyleReady,
    this.onReady,
    this.fallbackBuilder,
    super.key,
  });

  final Future<OlaMapsAvailability> availability;
  final List<RiderMarkerSpec> markers;
  final RiderRouteSpec? route;

  /// When set, the camera centers on this point (recenter/follow).
  final GeoPoint? followTarget;

  /// Points the camera should frame on style load / geometry change
  /// (rider + store + customer as applicable).
  final List<GeoPoint> fitPoints;

  final bool pitched;
  final double initialZoom;
  final VoidCallback? onUserPan;
  final VoidCallback? onStyleReady;

  /// Called once the style is loaded and the imperative handle works.
  final ValueChanged<RiderMapHandle>? onReady;
  final WidgetBuilder? fallbackBuilder;

  @override
  State<RiderMap> createState() => _RiderMapState();
}

/// Handle the parent screen keeps for imperative camera actions
/// (the recenter button).
class RiderMapHandle {
  RiderMapHandle(this._recenter);

  final VoidCallback _recenter;

  /// recenters the camera onto followTarget / refits fitPoints, ending
  /// any manual-pan suppression window.
  void recenter() => _recenter();
}

class _RiderMapState extends State<RiderMap> {
  ml.MapLibreMapController? _controller;
  bool _styleLoaded = false;
  bool _userMoved = false;
  _AppliedState _applied = const _AppliedState();

  /// Native objects by logical id, captured from addCircle/addLine —
  /// MapLibre assigns ids at add time, so updates/removals must go
  /// through the returned handles.
  final Map<String, ml.Circle> _nativeCircles = <String, ml.Circle>{};
  ml.Line? _nativeRoute;

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
              widget.followTarget ??
                  (widget.fitPoints.isNotEmpty
                      ? widget.fitPoints.first
                      : const GeoPoint(22.5726, 88.3639)),
            ),
            zoom: widget.initialZoom,
            tilt: widget.pitched ? 45 : 0,
          ),
          trackCameraPosition: true,
          compassEnabled: true,
          rotateGesturesEnabled: false,
          myLocationEnabled: false,
          onMapCreated: (ml.MapLibreMapController controller) {
            _controller = controller;
          },
          onStyleLoadedCallback: () {
            _styleLoaded = true;
            widget.onStyleReady?.call();
            widget.onReady?.call(
              RiderMapHandle(() {
                if (!mounted) return;
                _userMoved = false;
                unawaited(_apply());
              }),
            );
            unawaited(_apply());
          },
          onCameraIdle: () {
            // A rider drag must win over programmatic refits until they
            // recenter — same manual-pan suppression contract the
            // interim map had (design §24).
            if (mounted && !_userMoved) {
              setState(() => _userMoved = true);
            }
            widget.onUserPan?.call();
          },
        );
      },
    );
  }

  @override
  void didUpdateWidget(RiderMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_apply());
  }

  Future<void> _apply() async {
    final ml.MapLibreMapController? controller = _controller;
    if (controller == null || !_styleLoaded) return;

    // Route polyline (added before markers so markers render on top).
    final RiderRouteSpec? route = widget.route;
    if (route != null && route.points.length >= 2) {
      final List<ml.LatLng> line = route.points.map(_toLatLng).toList();
      final ml.LineOptions options = ml.LineOptions(
        geometry: line,
        lineColor: route.color,
        lineWidth: 5.0,
      );
      final ml.Line? native = _nativeRoute;
      if (native != null) {
        await controller.updateLine(native, options);
      } else {
        _nativeRoute = await controller.addLine(options);
      }
      _applied = _applied.withRoute(true);
    } else if (_nativeRoute != null) {
      await controller.removeLine(_nativeRoute!);
      _nativeRoute = null;
      _applied = _applied.withRoute(false);
    }

    // Markers, diffed by stable id.
    final Map<String, RiderMarkerSpec> wanted = <String, RiderMarkerSpec>{
      for (final RiderMarkerSpec m in widget.markers) m.id: m,
    };
    for (final String id in _nativeCircles.keys.toSet()) {
      if (!wanted.containsKey(id)) {
        await controller.removeCircle(_nativeCircles[id]!);
        _nativeCircles.remove(id);
        _applied = _applied.withoutMarker(id);
      }
    }
    for (final MapEntry<String, RiderMarkerSpec> entry in wanted.entries) {
      final ml.CircleOptions options = _circleOptions(entry.value);
      final ml.Circle? native = _nativeCircles[entry.key];
      if (native != null) {
        await controller.updateCircle(native, options);
      } else {
        _nativeCircles[entry.key] = await controller.addCircle(options);
        _applied = _applied.withMarker(entry.key);
      }
    }

    // Camera: fit the geometry once, follow the target when asked, and
    // honor pitch changes — never fighting a rider's manual pan.
    if (!_userMoved && widget.fitPoints.length >= 2) {
      final List<ml.LatLng> points = widget.fitPoints.map(_toLatLng).toList();
      final ml.LatLngBounds bounds = _boundsFor(points);
      await controller.moveCamera(
        ml.CameraUpdate.newLatLngBounds(
          bounds,
          left: 48,
          top: 96,
          right: 48,
          bottom: 96,
        ),
      );
    } else if (widget.followTarget != null) {
      final bool pitchChanged = widget.pitched != _applied.pitched;
      final bool targetChanged =
          _applied.followTarget == null ||
          _applied.followTarget != widget.followTarget;
      if (pitchChanged || (targetChanged && !_userMoved)) {
        await controller.animateCamera(
          ml.CameraUpdate.newCameraPosition(
            ml.CameraPosition(
              target: _toLatLng(widget.followTarget!),
              zoom: widget.initialZoom,
              tilt: widget.pitched ? 45 : 0,
            ),
          ),
        );
      }
    }
    _applied = _applied.withCamera(
      followTarget: widget.followTarget,
      pitched: widget.pitched,
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

  static ml.LatLngBounds _boundsFor(List<ml.LatLng> points) {
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
    return ml.LatLngBounds(
      southwest: ml.LatLng(minLat, minLng),
      northeast: ml.LatLng(maxLat, maxLng),
    );
  }
}

/// What the native style currently carries, for diffed updates.
class _AppliedState {
  const _AppliedState({
    this.routePresent = false,
    this.markerIds = const <String>{},
    this.followTarget,
    this.pitched = false,
  });

  final bool routePresent;
  final Set<String> markerIds;
  final GeoPoint? followTarget;
  final bool pitched;

  _AppliedState withRoute(bool present) => _AppliedState(
    routePresent: present,
    markerIds: markerIds,
    followTarget: followTarget,
    pitched: pitched,
  );

  _AppliedState withMarker(String id) => _AppliedState(
    routePresent: routePresent,
    markerIds: <String>{...markerIds, id},
    followTarget: followTarget,
    pitched: pitched,
  );

  _AppliedState withoutMarker(String id) => _AppliedState(
    routePresent: routePresent,
    markerIds: <String>{...markerIds}..remove(id),
    followTarget: followTarget,
    pitched: pitched,
  );

  _AppliedState withCamera({
    required GeoPoint? followTarget,
    required bool pitched,
  }) {
    return _AppliedState(
      routePresent: routePresent,
      markerIds: markerIds,
      followTarget: followTarget,
      pitched: pitched,
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
}) {
  final List<RiderMarkerSpec> markers = <RiderMarkerSpec>[];
  if (rider != null) {
    markers.add(
      RiderMarkerSpec(
        id: 'rider',
        position: rider,
        color: '#101114',
        radiusDp: 8,
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
      ),
    );
  }
  return markers;
}
