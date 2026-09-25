import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/maps/geo.dart';
import '../../../core/maps/geo_bounds.dart';
import '../../../core/maps/geo_point.dart';
import '../../../core/maps/marker_assets.dart';
import '../../../core/maps/route_service.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/assignment_status.dart';
import '../domain/delivery_address.dart';
import '../domain/delivery_order.dart';
import '../domain/store_info.dart';

/// Active route phase rendered by [ActiveDeliveryMapController].
enum LocationPhase { toStore, toCustomer, none }

/// A keyed marker entry used for idempotent rebuilds.
@immutable
class MarkerEntry {
  const MarkerEntry({
    required this.id,
    required this.position,
    required this.marker,
  });

  final String id;
  final GeoPoint position;
  final fm.Marker marker;

  @override
  bool operator ==(Object other) =>
      other is MarkerEntry && other.id == id && other.position == position;

  @override
  int get hashCode => Object.hash(id, position);
}

/// One leg of the rider's planned route: [from] → [to]. [points] is the
/// road-snapped polyline once [RouteService] resolves it, or the
/// straight-line placeholder `[from, to]` until then — mirrors
/// [RouteService.getRoute]'s own graceful-degradation contract so the
/// map always has *something* to draw immediately.
class _RouteLeg {
  _RouteLeg({required this.from, required this.to, required this.points});

  final GeoPoint from;
  final GeoPoint to;
  final List<GeoPoint> points;
}

/// Owns marker / polyline / phase state for the active delivery
/// map screen, including the road-snapped navigation polyline
/// (rider → destination via OSRM).
class ActiveDeliveryMapController extends ChangeNotifier {
  ActiveDeliveryMapController({
    required MarkerAssets markerAssets,
    RouteService? routeService,
  }) : _markerAssets = markerAssets,
       _routeService = routeService ?? RouteService();

  final MarkerAssets _markerAssets;
  final RouteService _routeService;

  GeoPoint? get riderPosition => _riderPosition;
  GeoPoint? _riderPosition;

  Map<String, MarkerEntry> get markers => _markers;
  Map<String, MarkerEntry> _markers = const <String, MarkerEntry>{};
  List<fm.Marker> get markerWidgets =>
      _markers.values.map((MarkerEntry e) => e.marker).toList(growable: false);

  List<fm.Polyline> get polylines => _polylines;
  List<fm.Polyline> _polylines = const <fm.Polyline>[];

  LocationPhase get phase => _phase;
  LocationPhase _phase = LocationPhase.none;

  bool get showRecenterButton => _showRecenterButton;
  bool _showRecenterButton = false;

  bool get customerLocationApproximate => _customerLocationApproximate;
  bool _customerLocationApproximate = false;

  GeoBounds? get phaseBounds => _phaseBounds;
  GeoBounds? _phaseBounds;

  GeoPoint? get storePosition => _storePosition;
  GeoPoint? _storePosition;

  GeoPoint? get customerPosition => _customerPosition;
  GeoPoint? _customerPosition;

  /// Distance in metres from the rider to the active destination.
  /// `null` when either side is unknown.
  double? get distanceMeters => _distanceMeters;
  double? _distanceMeters;

  /// Estimated travel time in minutes, computed from the road
  /// polyline length divided by an assumed 25 km/h average city
  /// speed. `null` when no route is loaded.
  int? get etaMinutes => _etaMinutes;
  int? _etaMinutes;

  String? _currentOrderId;

  /// The rider's full planned route as a sequence of legs — rider →
  /// stop 1 → stop 2 → … Single-order trips simply have one leg, so
  /// this subsumes what used to be a dedicated single-destination
  /// cache. Road-snapped as [_maybeRefreshLegs] resolves each leg;
  /// straight-line placeholders otherwise.
  List<_RouteLeg> _legs = const <_RouteLeg>[];

  /// Rider position / destination set the last leg fetch was issued
  /// for — lets [_maybeRefreshLegs] skip redundant network calls when
  /// nothing meaningful has changed.
  GeoPoint? _legsFetchOrigin;
  List<GeoPoint> _legsFetchDestinations = const <GeoPoint>[];

  /// Bumped on every [_maybeRefreshLegs] call so a slow, superseded
  /// fetch can detect it's stale and discard its result instead of
  /// clobbering a newer one (the plan or rider position can change
  /// again while a fetch is still in flight).
  int _legsFetchToken = 0;

  static const double _riderMoveThresholdMeters = 5;
  static const double _routeRefetchThresholdMeters = 50;
  static const double _averageSpeedKmh = 25.0;

  // ---------------------------------------------------------------------------
  // Public mutations
  // ---------------------------------------------------------------------------

  void setShowRecenterButton(bool value) {
    if (_showRecenterButton == value) return;
    _showRecenterButton = value;
    notifyListeners();
  }

  void applyOrder(DeliveryOrder order, StoreInfo? store) {
    final bool orderChanged = _currentOrderId != order.orderId;
    _currentOrderId = order.orderId;

    GeoPoint? resolvedStore;
    final DeliveryAddress storeAddr = order.storeAddress;
    if (storeAddr.lat != null && storeAddr.lng != null) {
      resolvedStore = GeoPoint(storeAddr.lat!, storeAddr.lng!);
    } else if (store != null && store.isConfigured) {
      resolvedStore = GeoPoint(store.lat, store.lng);
    }

    GeoPoint? resolvedCustomer;
    bool customerLocationMissing = false;
    final DeliveryAddress customerAddr = order.customerAddress;
    if (customerAddr.lat != null && customerAddr.lng != null) {
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

    _markers = _buildMarkers(
      rider: _riderPosition,
      store: resolvedStore,
      customer: resolvedCustomer,
    );
    _recomputeRoute();
    _phaseBounds = _computePhaseBounds(_riderPosition, _plannedDestinations);
    _recomputeDistanceAndEta();
    _polylines = _buildPolylinesFromLegs();

    if (orderChanged) {
      _showRecenterButton = false;
    }

    notifyListeners();

    // Fire-and-forget road-route fetch; updates the polyline as OSRM
    // resolves each leg.
    unawaited(_maybeRefreshLegs());
  }

  void updateRiderPosition(GeoPoint next) {
    final GeoPoint? prev = _riderPosition;
    if (prev != null) {
      final double meters = Geo.distanceMeters(prev, next);
      if (meters < _riderMoveThresholdMeters) return;
    }
    _riderPosition = next;

    _markers = _buildMarkers(
      rider: next,
      store: _storePosition,
      customer: _customerPosition,
    );
    _recomputeRoute();
    _phaseBounds = _computePhaseBounds(next, _plannedDestinations);
    _recomputeDistanceAndEta();
    _polylines = _buildPolylinesFromLegs();
    notifyListeners();

    unawaited(_maybeRefreshLegs());
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// The ordered list of places the rider still has to physically go —
  /// the input to route-leg computation. Single-order world (blueprint
  /// §10): one store bound in `toStore`, one customer in `toCustomer`.
  List<GeoPoint> get _plannedDestinations {
    switch (_phase) {
      case LocationPhase.toStore:
        final GeoPoint? store = _storePosition;
        return store == null ? const <GeoPoint>[] : <GeoPoint>[store];
      case LocationPhase.toCustomer:
        final GeoPoint? customer = _customerPosition;
        return customer == null ? const <GeoPoint>[] : <GeoPoint>[customer];
      case LocationPhase.none:
        return const <GeoPoint>[];
    }
  }

  /// Rebuilds [_legs] for the current rider position / planned stops,
  /// reusing already-fetched road points for any leg whose endpoints
  /// haven't changed (so a GPS tick doesn't flash the polyline back to
  /// a straight line every time). New/changed legs start as straight-
  /// line placeholders until [_maybeRefreshLegs] resolves them.
  void _recomputeRoute() {
    final GeoPoint? rider = _riderPosition;
    final List<GeoPoint> destinations = _plannedDestinations;
    if (rider == null || destinations.isEmpty) {
      _legs = const <_RouteLeg>[];
      return;
    }

    final List<GeoPoint> points = <GeoPoint>[rider, ...destinations];
    final List<_RouteLeg> next = <_RouteLeg>[];
    for (int i = 0; i < points.length - 1; i++) {
      final GeoPoint from = points[i];
      final GeoPoint to = points[i + 1];
      final _RouteLeg? existing = i < _legs.length ? _legs[i] : null;
      final bool reusable =
          existing != null && existing.from == from && existing.to == to;
      next.add(
        _RouteLeg(
          from: from,
          to: to,
          points: reusable ? existing.points : <GeoPoint>[from, to],
        ),
      );
    }
    _legs = next;
  }

  /// Fetches real road-snapped geometry for every leg in [_legs],
  /// skipped entirely when neither the destination plan nor the
  /// rider's position has meaningfully changed since the last fetch
  /// (mirrors the old single-leg drift/dest-change guard).
  Future<void> _maybeRefreshLegs() async {
    final GeoPoint? rider = _riderPosition;
    final List<GeoPoint> destinations = _plannedDestinations;
    if (rider == null || destinations.isEmpty) {
      _legsFetchOrigin = null;
      _legsFetchDestinations = const <GeoPoint>[];
      return;
    }

    final bool destinationsChanged = !listEquals(
      _legsFetchDestinations,
      destinations,
    );
    final bool riderDrifted =
        _legsFetchOrigin == null ||
        Geo.distanceMeters(_legsFetchOrigin!, rider) >=
            _routeRefetchThresholdMeters;
    if (!destinationsChanged && !riderDrifted) return;

    final int token = ++_legsFetchToken;
    _legsFetchOrigin = rider;
    _legsFetchDestinations = List<GeoPoint>.of(destinations);

    final List<GeoPoint> points = <GeoPoint>[rider, ...destinations];
    final List<List<GeoPoint>> fetched =
        await Future.wait(<Future<List<GeoPoint>>>[
          for (int i = 0; i < points.length - 1; i++)
            _routeService.getRoute(points[i], points[i + 1]),
        ]);

    // A newer fetch superseded this one (plan or position changed again
    // while OSRM was thinking) — discard rather than clobber fresher state.
    if (token != _legsFetchToken) return;

    _legs = <_RouteLeg>[
      for (int i = 0; i < points.length - 1; i++)
        _RouteLeg(from: points[i], to: points[i + 1], points: fetched[i]),
    ];
    _recomputeDistanceAndEta();
    _polylines = _buildPolylinesFromLegs();
    notifyListeners();
  }

  Map<String, MarkerEntry> _buildMarkers({
    required GeoPoint? rider,
    required GeoPoint? store,
    required GeoPoint? customer,
  }) {
    final Map<String, MarkerEntry> out = <String, MarkerEntry>{};
    if (rider != null) {
      out['rider'] = MarkerEntry(
        id: 'rider',
        position: rider,
        marker: fm.Marker(
          key: const ValueKey<String>('rider'),
          point: rider.toLatLng(),
          width: MarkerAssets.riderSizeDp,
          height: MarkerAssets.riderSizeDp,
          alignment: Alignment.center,
          child: _markerAssets.riderMarker(),
        ),
      );
    }
    if (store != null) {
      out['store'] = MarkerEntry(
        id: 'store',
        position: store,
        marker: fm.Marker(
          key: const ValueKey<String>('store'),
          point: store.toLatLng(),
          width: MarkerAssets.otherSizeDp,
          height: MarkerAssets.otherSizeDp,
          alignment: Alignment.center,
          child: _markerAssets.storeMarker(),
        ),
      );
    }
    if (customer != null) {
      out['customer'] = MarkerEntry(
        id: 'customer',
        position: customer,
        marker: fm.Marker(
          key: const ValueKey<String>('customer'),
          point: customer.toLatLng(),
          width: MarkerAssets.otherSizeDp,
          height: MarkerAssets.otherSizeDp,
          alignment: Alignment.center,
          child: _markerAssets.customerMarker(),
        ),
      );
    }
    return out;
  }

  /// Concatenates every leg in [_legs] into one continuous polyline —
  /// the rider's full planned journey (rider → stop 1 → stop 2 → …),
  /// not just the next hop. Adjacent legs share an endpoint, so that
  /// shared point is only emitted once.
  List<fm.Polyline> _buildPolylinesFromLegs() {
    if (_legs.isEmpty) return const <fm.Polyline>[];

    final List<GeoPoint> combined = <GeoPoint>[];
    for (final _RouteLeg leg in _legs) {
      if (leg.points.isEmpty) continue;
      if (combined.isNotEmpty && leg.points.first == combined.last) {
        combined.addAll(leg.points.skip(1));
      } else {
        combined.addAll(leg.points);
      }
    }
    if (combined.length < 2) return const <fm.Polyline>[];

    final List<ll.LatLng> latLngs = combined
        .map((GeoPoint p) => p.toLatLng())
        .toList(growable: false);

    return <fm.Polyline>[
      // Soft white halo so the route stays readable on busy tiles.
      fm.Polyline(
        points: latLngs,
        color: AppColors.white.withValues(alpha: 0.85),
        strokeWidth: 9,
      ),
      fm.Polyline(points: latLngs, color: AppColors.mapBlue, strokeWidth: 5),
    ];
  }

  /// Bounding box around the rider and every planned destination, so
  /// the camera can fit the *whole* route on screen when it's freshly
  /// computed (item: "rider can see what route they follow" at accept
  /// time) — not just the rider and the immediate next stop.
  GeoBounds? _computePhaseBounds(GeoPoint? rider, List<GeoPoint> destinations) {
    final List<GeoPoint> points = <GeoPoint>[?rider, ...destinations];
    if (points.isEmpty) return null;
    if (points.length == 1) return Geo.inflatePoint(points.first);

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final GeoPoint p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return GeoBounds(
      southwest: GeoPoint(minLat, minLng),
      northeast: GeoPoint(maxLat, maxLng),
    );
  }

  /// Distance/ETA reflect the *immediate next leg* only (rider → the
  /// closest upcoming stop) — what the top-bar stat is actually for —
  /// even when [_legs] holds the rider's whole multi-stop plan.
  void _recomputeDistanceAndEta() {
    if (_legs.isEmpty) {
      _distanceMeters = null;
      _etaMinutes = null;
      return;
    }
    final _RouteLeg firstLeg = _legs.first;
    final double meters = firstLeg.points.length >= 2
        ? _polylineLengthMeters(firstLeg.points)
        : Geo.distanceMeters(firstLeg.from, firstLeg.to);
    _distanceMeters = meters;
    final double minutes = (meters / 1000.0) / _averageSpeedKmh * 60.0;
    _etaMinutes = minutes < 1 ? 1 : minutes.ceil().clamp(1, 999);
  }

  static double _polylineLengthMeters(List<GeoPoint> pts) {
    double total = 0;
    for (int i = 1; i < pts.length; i++) {
      total += Geo.distanceMeters(pts[i - 1], pts[i]);
    }
    return total;
  }
}
