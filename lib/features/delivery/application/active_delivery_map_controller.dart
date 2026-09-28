import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/maps/geo.dart';
import '../../../core/maps/geo_point.dart';
import '../../../core/maps/rider_map.dart';
import '../../../core/maps/rider_maps_service.dart';
import '../../../core/maps/route_geometry.dart';
import '../domain/assignment_status.dart';
import '../domain/delivery_address.dart';
import '../domain/delivery_order.dart';
import '../domain/store_info.dart';

/// Active route phase rendered by [ActiveDeliveryMapController].
enum LocationPhase { toStore, toCustomer, none }

/// Where the road route for the current phase stands.
enum MapRouteStatus {
  /// No destination for this phase (delivered / cancelled / no coordinates).
  none,

  /// There is a destination but no usable GPS fix yet.
  awaitingLocation,

  /// Fetching the first road route for this destination.
  loading,

  /// A real Ola road route is available (distance / ETA are derived from it).
  ready,

  /// Ola could not produce a route. Nothing is drawn — never a fake line.
  failed,
}

/// Owns marker / route / phase state for the active delivery map
/// screen. Produces MapLibre-agnostic [RiderMarkerSpec]s and route
/// points that [RiderMap] applies to the native style.
///
/// Routing contract:
/// - the route is always real road geometry from the backend's Ola
///   Directions proxy, from the rider's latest valid GPS fix to the
///   current phase's destination (store, then customer after pickup);
/// - distance and ETA are read off that route (the rider is snapped onto
///   it, so both count down as the rider progresses) — there is no
///   straight-line estimate;
/// - a rider who strays more than [offRouteThresholdMeters] from the
///   route triggers a throttled re-fetch from the current position;
/// - if no route can be fetched, nothing is drawn and [routeStatus] is
///   [MapRouteStatus.failed] so the UI can offer a retry.
class ActiveDeliveryMapController extends ChangeNotifier {
  ActiveDeliveryMapController({
    required RiderMapsService mapsService,
    DateTime Function()? clock,
  }) : _mapsService = mapsService,
       _now = clock ?? DateTime.now;

  final RiderMapsService _mapsService;
  final DateTime Function() _now;

  GeoPoint? get riderPosition => _riderPosition;
  GeoPoint? _riderPosition;

  /// Latest reliable travel direction in degrees clockwise from north, or
  /// null when unknown (stationary / no compass-grade fix yet).
  double? get riderHeading => _riderHeading;
  double? _riderHeading;

  /// Markers to render on the map (rider + the phase's destination).
  List<RiderMarkerSpec> get markers => _markers;
  List<RiderMarkerSpec> _markers = const <RiderMarkerSpec>[];

  /// The not-yet-travelled part of the road route for the active phase,
  /// or null while none is available (only the rider marker renders).
  RiderRouteSpec? get route => _route;
  RiderRouteSpec? _route;

  /// Points an overview camera should frame: the rider and everything
  /// still ahead of them on the route (or just the destination while the
  /// route is unresolved).
  List<GeoPoint> get fitPoints => _fitPoints;
  List<GeoPoint> _fitPoints = const <GeoPoint>[];

  /// Bumped whenever the map should re-frame the whole journey: the first
  /// route of a new destination (accept → pickup → customer). Not bumped by
  /// a mid-trip reroute, so the camera never jumps while the rider follows.
  int get overviewToken => _overviewToken;
  int _overviewToken = 0;

  LocationPhase get phase => _phase;
  LocationPhase _phase = LocationPhase.none;

  MapRouteStatus get routeStatus => _routeStatus;
  MapRouteStatus _routeStatus = MapRouteStatus.none;

  bool get showRecenterButton => _showRecenterButton;
  bool _showRecenterButton = false;

  bool get customerLocationApproximate => _customerLocationApproximate;
  bool _customerLocationApproximate = false;

  GeoPoint? get storePosition => _storePosition;
  GeoPoint? _storePosition;

  GeoPoint? get customerPosition => _customerPosition;
  GeoPoint? _customerPosition;

  /// Remaining road distance in metres along the active route. `null`
  /// until a real route exists.
  double? get distanceMeters => _distanceMeters;
  double? _distanceMeters;

  /// Estimated minutes remaining, scaled from the Ola route duration by
  /// the share of the route still ahead. `null` until a real route exists.
  int? get etaMinutes => _etaMinutes;
  int? _etaMinutes;

  String? _currentOrderId;

  // Active route (full polyline as returned by Ola) and its totals.
  List<GeoPoint> _routePoints = const <GeoPoint>[];
  /// Ola's own leg distance / duration for the whole route.
  double _routeTotalMeters = 0;
  int _routeDurationSeconds = 0;

  /// Length of the returned polyline. Slightly different from Ola's leg
  /// distance (the overview polyline is simplified), so progress is tracked
  /// as a *share* of this and applied to Ola's figures — the header then
  /// starts at exactly what Ola reported and counts down smoothly.
  double _routeGeometryMeters = 0;
  RouteProjection? _projection;

  /// Destination the current route / in-flight fetch belongs to.
  GeoPoint? _routeDestination;

  /// Bumped on every fetch so a slow, superseded fetch is discarded.
  int _routeFetchToken = 0;
  bool _fetching = false;
  DateTime? _lastFetchStartedAt;
  int _offRouteStreak = 0;

  static const double _riderMoveThresholdMeters = 5;

  /// Distance from the route beyond which the rider counts as off it —
  /// wide enough to ignore urban GPS drift and parallel-lane noise.
  static const double offRouteThresholdMeters = 70;

  /// Consecutive off-route fixes required before rerouting (one GPS spike
  /// must not throw away a good route).
  static const int _offRouteFixesRequired = 2;

  /// Minimum gap between automatic route requests (reroute / retry) so a
  /// stream of GPS ticks never becomes a stream of Ola calls.
  static const Duration minRefetchInterval = Duration(seconds: 15);

  // ---------------------------------------------------------------------------
  // Public mutations
  // ---------------------------------------------------------------------------

  void setShowRecenterButton(bool value) {
    if (_showRecenterButton == value) return;
    _showRecenterButton = value;
    notifyListeners();
  }

  /// Manual retry (top-bar "Retry"): fetch now, ignoring the throttle.
  void retryRoute() {
    if (_destination == null) return;
    _requestRoute(force: true);
    notifyListeners();
  }

  void applyOrder(DeliveryOrder order, StoreInfo? store) {
    final bool orderChanged = _currentOrderId != order.orderId;
    _currentOrderId = order.orderId;

    GeoPoint? resolvedStore;
    final DeliveryAddress storeAddr = order.storeAddress;
    if (_validCoordinate(storeAddr.lat, storeAddr.lng)) {
      resolvedStore = GeoPoint(storeAddr.lat!, storeAddr.lng!);
    } else if (store != null && store.isConfigured) {
      resolvedStore = GeoPoint(store.lat, store.lng);
    }

    GeoPoint? resolvedCustomer;
    bool customerLocationMissing = false;
    final DeliveryAddress customerAddr = order.customerAddress;
    if (_validCoordinate(customerAddr.lat, customerAddr.lng)) {
      resolvedCustomer = GeoPoint(customerAddr.lat!, customerAddr.lng!);
    } else {
      customerLocationMissing = true;
      resolvedCustomer = null;
    }

    final LocationPhase nextPhase;
    switch (order.assignmentStatus) {
      case AssignmentStatus.assigned:
      case AssignmentStatus.accepted:
        nextPhase = resolvedStore == null
            ? LocationPhase.none
            : LocationPhase.toStore;
      case AssignmentStatus.inTransit:
        nextPhase = resolvedCustomer == null
            ? LocationPhase.none
            : LocationPhase.toCustomer;
      case AssignmentStatus.delivered:
      case AssignmentStatus.cancelled:
        nextPhase = LocationPhase.none;
    }

    _storePosition = resolvedStore;
    _customerPosition = resolvedCustomer;
    _customerLocationApproximate = customerLocationMissing;
    _phase = nextPhase;

    // A different destination (pickup → customer, or a new order) makes the
    // old route meaningless: drop it before anything renders it.
    final GeoPoint? destination = _destination;
    if (destination == null ||
        _routeDestination == null ||
        Geo.distanceMeters(_routeDestination!, destination) >= 1) {
      _clearRoute();
      _routeDestination = destination;
      _routeStatus = destination == null
          ? MapRouteStatus.none
          : (_riderPosition == null
                ? MapRouteStatus.awaitingLocation
                : MapRouteStatus.loading);
      if (destination != null && _riderPosition != null) {
        _requestRoute(force: true);
      }
    }

    _rebuild();

    if (orderChanged) {
      _showRecenterButton = false;
    }

    notifyListeners();
  }

  /// Feeds a GPS fix. Unusable fixes (NaN, out of range, 0,0) are ignored so
  /// they can never place the rider marker or seed a route.
  void updateRiderPosition(GeoPoint next) {
    if (!_validCoordinate(next.latitude, next.longitude)) return;
    final GeoPoint? prev = _riderPosition;
    if (prev != null) {
      final double meters = Geo.distanceMeters(prev, next);
      if (meters < _riderMoveThresholdMeters) return;
    }
    _riderPosition = next;

    final GeoPoint? destination = _destination;
    if (destination != null) {
      if (_routePoints.length >= 2) {
        _projection = RouteGeometry.project(_routePoints, next);
        _trackOffRoute();
      } else if (!_fetching) {
        // No route yet. Either the first usable fix arrived after the order
        // was applied (fetch right away) or the last attempt failed (retry,
        // throttled so GPS ticks don't become Ola calls).
        _requestRoute(force: _routeStatus != MapRouteStatus.failed);
      }
    }

    _rebuild();
    notifyListeners();
  }

  /// Feeds the rider's travel direction (degrees clockwise from north);
  /// `null` keeps the last reliable value.
  void updateRiderHeading(double? degrees) {
    if (degrees == null || !degrees.isFinite) return;
    final double normalized = ((degrees % 360) + 360) % 360;
    final double? prev = _riderHeading;
    if (prev != null) {
      final double delta = ((normalized - prev + 540) % 360) - 180;
      if (delta.abs() < 4) return;
    }
    _riderHeading = normalized;
    _rebuildMarkers();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  GeoPoint? get _destination => switch (_phase) {
    LocationPhase.toStore => _storePosition,
    LocationPhase.toCustomer => _customerPosition,
    LocationPhase.none => null,
  };

  static bool _validCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    return lat != 0 || lng != 0;
  }

  void _clearRoute() {
    _routeFetchToken++; // orphan any in-flight fetch
    _fetching = false;
    _routePoints = const <GeoPoint>[];
    _routeTotalMeters = 0;
    _routeDurationSeconds = 0;
    _routeGeometryMeters = 0;
    _projection = null;
    _offRouteStreak = 0;
    _lastFetchStartedAt = null;
  }

  void _trackOffRoute() {
    final RouteProjection? projection = _projection;
    if (projection == null) return;
    if (projection.offRouteMeters > offRouteThresholdMeters) {
      _offRouteStreak++;
      if (_offRouteStreak >= _offRouteFixesRequired) {
        _requestRoute(force: false);
      }
    } else {
      _offRouteStreak = 0;
    }
  }

  void _rebuild() {
    _rebuildMarkers();
    _rebuildRouteDerived();
  }

  void _rebuildMarkers() {
    // The map shows the destination the rider is heading to — the store
    // during pickup, the customer once in transit. The other marker would
    // only be noise (and, pre-accept, a privacy leak).
    _markers = riderMarkersForOrder(
      rider: _riderPosition,
      riderHeading: _riderHeading,
      store: _phase == LocationPhase.toStore
          ? (_storePosition == null
                ? null
                : DeliveryAddress(
                    name: 'Store',
                    address: '',
                    lat: _storePosition!.latitude,
                    lng: _storePosition!.longitude,
                  ))
          : null,
      customer: _phase == LocationPhase.toCustomer
          ? (_customerPosition == null
                ? null
                : DeliveryAddress(
                    name: 'Customer',
                    address: '',
                    lat: _customerPosition!.latitude,
                    lng: _customerPosition!.longitude,
                  ))
          : null,
    );
  }

  /// Route line, distance, ETA and camera-fit points from the active route
  /// and the rider's projection onto it.
  void _rebuildRouteDerived() {
    final GeoPoint? destination = _destination;
    final RouteProjection? projection = _projection;

    if (_routePoints.length >= 2 && projection != null) {
      final List<GeoPoint> ahead = RouteGeometry.remainingPoints(
        _routePoints,
        projection,
      );
      _route = RiderRouteSpec(points: ahead);
      final double share = _routeGeometryMeters <= 0
          ? 1.0
          : (projection.remainingMeters / _routeGeometryMeters).clamp(0.0, 1.0);
      // Off-route detours count: the rider still has to get back.
      _distanceMeters = _routeTotalMeters * share + projection.offRouteMeters;
      final double seconds = _routeDurationSeconds * share;
      _etaMinutes = (seconds / 60.0).ceil().clamp(1, 999);
      _fitPoints = <GeoPoint>[?_riderPosition, ...ahead];
    } else if (_routePoints.length >= 2) {
      // Route exists but the rider has no fix yet (reroute after a fix
      // was lost) — show it whole, with the fetch-time totals.
      _route = RiderRouteSpec(points: _routePoints);
      _distanceMeters = _routeTotalMeters;
      _etaMinutes = (_routeDurationSeconds / 60.0).ceil().clamp(1, 999);
      _fitPoints = List<GeoPoint>.of(_routePoints);
    } else {
      _route = null;
      _distanceMeters = null;
      _etaMinutes = null;
      _fitPoints = <GeoPoint>[?_riderPosition, ?destination];
    }
  }

  /// Starts a road-route fetch for the active destination from the rider's
  /// latest fix. [force] skips the throttle (new destination / manual retry).
  void _requestRoute({required bool force}) {
    final GeoPoint? origin = _riderPosition;
    final GeoPoint? destination = _destination;
    if (origin == null || destination == null) return;
    if (_fetching && !force) return;
    final DateTime now = _now();
    final DateTime? last = _lastFetchStartedAt;
    if (!force && last != null && now.difference(last) < minRefetchInterval) {
      return;
    }

    _lastFetchStartedAt = now;
    _fetching = true;
    final int token = ++_routeFetchToken;
    final bool isReroute = _routePoints.length >= 2;
    _routeDestination = destination;
    if (!isReroute) _routeStatus = MapRouteStatus.loading;

    unawaited(() async {
      final RiderRoute? fetched = await _mapsService.getRoute(
        origin,
        destination,
      );
      if (token != _routeFetchToken) return; // superseded / destination moved
      _fetching = false;
      if (fetched == null || fetched.points.length < 2) {
        // Keep showing a previous good route on a failed reroute; with none,
        // surface the failure rather than drawing anything invented.
        if (!isReroute) _routeStatus = MapRouteStatus.failed;
        notifyListeners();
        return;
      }
      _routePoints = fetched.points;
      _routeDurationSeconds = fetched.durationSeconds;
      _routeGeometryMeters = RouteGeometry.lengthMeters(fetched.points);
      _routeTotalMeters = fetched.distanceMeters > 0
          ? fetched.distanceMeters.toDouble()
          : _routeGeometryMeters;
      _routeStatus = MapRouteStatus.ready;
      _offRouteStreak = 0;
      final GeoPoint? rider = _riderPosition;
      _projection = rider == null
          ? null
          : RouteGeometry.project(_routePoints, rider);
      if (!isReroute) _overviewToken++;
      _rebuildRouteDerived();
      notifyListeners();
    }());
  }
}
