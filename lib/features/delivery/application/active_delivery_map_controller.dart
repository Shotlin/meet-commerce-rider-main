import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/maps/geo.dart';
import '../../../core/maps/geo_point.dart';
import '../../../core/maps/rider_map.dart';
import '../../../core/maps/rider_maps_service.dart';
import '../domain/assignment_status.dart';
import '../domain/delivery_address.dart';
import '../domain/delivery_order.dart';
import '../domain/store_info.dart';

/// Active route phase rendered by [ActiveDeliveryMapController].
enum LocationPhase { toStore, toCustomer, none }

/// Owns marker / route / phase state for the active delivery map
/// screen. Produces MapLibre-agnostic [RiderMarkerSpec]s and route
/// points that [RiderMap] applies to the native style — the road-snapped
/// route comes from the backend's Ola Directions proxy (Big Phase 12),
/// with the same straight-line fallback contract the interim OSRM
/// service had so the map always has something to draw.
class ActiveDeliveryMapController extends ChangeNotifier {
  ActiveDeliveryMapController({required RiderMapsService mapsService})
    : _mapsService = mapsService;

  final RiderMapsService _mapsService;

  GeoPoint? get riderPosition => _riderPosition;
  GeoPoint? _riderPosition;

  /// Markers to render on the map (rider/store/customer as available).
  List<RiderMarkerSpec> get markers => _markers;
  List<RiderMarkerSpec> _markers = const <RiderMarkerSpec>[];

  /// The road-snapped route polyline for the active phase, or null
  /// while it hasn't resolved yet (the rider marker alone renders).
  RiderRouteSpec? get route => _route;
  RiderRouteSpec? _route;

  /// Points the camera should frame (rider + destination).
  List<GeoPoint> get fitPoints => _fitPoints;
  List<GeoPoint> _fitPoints = const <GeoPoint>[];

  LocationPhase get phase => _phase;
  LocationPhase _phase = LocationPhase.none;

  bool get showRecenterButton => _showRecenterButton;
  bool _showRecenterButton = false;

  bool get customerLocationApproximate => _customerLocationApproximate;
  bool _customerLocationApproximate = false;

  GeoPoint? get storePosition => _storePosition;
  GeoPoint? _storePosition;

  GeoPoint? get customerPosition => _customerPosition;
  GeoPoint? _customerPosition;

  /// Distance in metres from the rider to the active destination —
  /// road distance once the Ola route resolves, haversine before that.
  /// `null` when either side is unknown.
  double? get distanceMeters => _distanceMeters;
  double? _distanceMeters;

  /// Estimated travel time in minutes, from the Ola route duration
  /// when available, else the road/haversine distance at an assumed
  /// 25 km/h average city speed. `null` when no destination is known.
  int? get etaMinutes => _etaMinutes;
  int? _etaMinutes;

  String? _currentOrderId;

  /// Destination the active route was fetched for — a phase change or
  /// a different destination triggers a fresh Ola directions fetch.
  GeoPoint? _routeDestination;

  /// Bumped on every route fetch so a slow, superseded fetch discards
  /// its result instead of clobbering a newer one.
  int _routeFetchToken = 0;

  static const double _riderMoveThresholdMeters = 5;
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

    _rebuildMarkers();
    _rebuildFitPoints();
    _recomputeDistanceAndEta();
    _syncRoute();

    if (orderChanged) {
      _showRecenterButton = false;
    }

    notifyListeners();
  }

  void updateRiderPosition(GeoPoint next) {
    final GeoPoint? prev = _riderPosition;
    if (prev != null) {
      final double meters = Geo.distanceMeters(prev, next);
      if (meters < _riderMoveThresholdMeters) return;
    }
    _riderPosition = next;

    _rebuildMarkers();
    _rebuildFitPoints();
    _recomputeDistanceAndEta();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _rebuildMarkers() {
    // §11/§12: the map shows the destination the rider is heading to —
    // the store during pickup, the customer once in transit. The other
    // marker would only be noise (and, pre-accept, a privacy leak).
    _markers = riderMarkersForOrder(
      rider: _riderPosition,
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

  void _rebuildFitPoints() {
    _fitPoints = <GeoPoint>[
      ?_riderPosition,
      if (_phase == LocationPhase.toStore) ?_storePosition,
      if (_phase == LocationPhase.toCustomer) ?_customerPosition,
    ];
  }

  void _recomputeDistanceAndEta() {
    final GeoPoint? destination = switch (_phase) {
      LocationPhase.toStore => _storePosition,
      LocationPhase.toCustomer => _customerPosition,
      LocationPhase.none => null,
    };
    if (_riderPosition == null || destination == null) {
      _distanceMeters = null;
      _etaMinutes = null;
      return;
    }
    // Haversine immediately (honest straight-line estimate); the Ola
    // route fetch overrides both values with road truth when it lands.
    final double meters = Geo.distanceMeters(_riderPosition!, destination);
    _distanceMeters = meters;
    _etaMinutes = _minutesFor(meters);
  }

  void _syncRoute() {
    final GeoPoint? origin = _riderPosition;
    final GeoPoint? destination = switch (_phase) {
      LocationPhase.toStore => _storePosition,
      LocationPhase.toCustomer => _customerPosition,
      LocationPhase.none => null,
    };
    if (origin == null || destination == null) return;
    if (_routeDestination != null &&
        _route != null &&
        Geo.distanceMeters(_routeDestination!, destination) < 1) {
      return; // same destination — the loaded route still serves
    }
    _routeDestination = destination;
    final int token = ++_routeFetchToken;
    unawaited(() async {
      final RiderRoute route = await _mapsService.getRoute(origin, destination);
      if (token != _routeFetchToken) return; // superseded
      _route = RiderRouteSpec(points: route.points);
      _distanceMeters = route.distanceMeters.toDouble();
      _etaMinutes = _minutesFor(route.distanceMeters.toDouble());
      notifyListeners();
    }());
  }

  int _minutesFor(double meters) {
    final double minutes = (meters / 1000.0) / _averageSpeedKmh * 60.0;
    return minutes < 1 ? 1 : minutes.ceil().clamp(1, 999);
  }
}
