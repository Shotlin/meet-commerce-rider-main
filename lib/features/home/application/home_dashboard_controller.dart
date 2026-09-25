import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../delivery/data/delivery_api.dart';
import '../../delivery/domain/delivery_order.dart';
import '../../delivery/domain/rider_earnings.dart';
import '../../delivery/domain/rider_profile.dart';
import '../../delivery/domain/rider_stats.dart';
import '../../delivery/domain/store_info.dart';

/// Coordinates the five parallel calls that populate the rider home
/// dashboard (R5.1).
///
/// `refresh()` fans out:
///
/// - `GET /delivery/profile`     -> [profile]
/// - `GET /delivery/stats`       -> [stats]
/// - `GET /delivery/earnings?period=today` -> [earningsToday]
/// - `GET /delivery/orders`      -> [orders]
/// - `GET /delivery/store-info`  -> [store]
///
/// Each call captures its result (or its error) into a dedicated field
/// so that one failed card never poisons the rest of the dashboard
/// (R5.3). Loading state is tracked per card so the UI can show a
/// skeleton on a single card while the rest stay populated on a
/// retry-from-error.
///
/// This is a plain [ChangeNotifier] (no Riverpod) so it can be
/// unit-tested in pure Dart without a Flutter widget tree.
class HomeDashboardController extends ChangeNotifier {
  /// Wires the controller to its [api] dependency.
  HomeDashboardController({required DeliveryApi api}) : _api = api;

  final DeliveryApi _api;

  // ---------------------------------------------------------------------------
  // Data fields
  // ---------------------------------------------------------------------------

  RiderProfile? _profile;
  RiderStats? _stats;
  RiderEarnings? _earningsToday;
  List<DeliveryOrder> _orders = const <DeliveryOrder>[];
  StoreInfo? _store;

  /// Latest profile from `/delivery/profile`. Null until first
  /// successful fetch.
  RiderProfile? get profile => _profile;

  /// Latest stats from `/delivery/stats`. Null until first successful
  /// fetch or after a failure.
  RiderStats? get stats => _stats;

  /// Earnings for the current day from `/delivery/earnings?period=today`.
  RiderEarnings? get earningsToday => _earningsToday;

  /// Latest orders from `/delivery/orders`. Defaults to an empty list
  /// when no fetch has succeeded yet.
  List<DeliveryOrder> get orders => List<DeliveryOrder>.unmodifiable(_orders);

  /// Latest store info from `/delivery/store-info`. Null until first
  /// successful fetch.
  StoreInfo? get store => _store;

  // ---------------------------------------------------------------------------
  // Per-card error / loading flags
  // ---------------------------------------------------------------------------

  String? _profileError;
  String? _statsError;
  String? _earningsError;
  String? _ordersError;
  String? _storeError;

  /// Error from the latest profile fetch. Null when the last fetch
  /// succeeded or none has run yet.
  String? get profileError => _profileError;

  /// Error from the latest stats fetch.
  String? get statsError => _statsError;

  /// Error from the latest today-earnings fetch.
  String? get earningsError => _earningsError;

  /// Error from the latest orders fetch.
  String? get ordersError => _ordersError;

  /// Error from the latest store-info fetch.
  String? get storeError => _storeError;

  bool _profileLoading = false;
  bool _statsLoading = false;
  bool _earningsLoading = false;
  bool _ordersLoading = false;
  bool _storeLoading = false;

  /// Whether the profile call is in flight.
  bool get profileLoading => _profileLoading;

  /// Whether the stats call is in flight.
  bool get statsLoading => _statsLoading;

  /// Whether the today-earnings call is in flight.
  bool get earningsLoading => _earningsLoading;

  /// Whether the orders call is in flight.
  bool get ordersLoading => _ordersLoading;

  /// Whether the store-info call is in flight.
  bool get storeLoading => _storeLoading;

  /// Aggregate flag — true while any of the five calls is in flight.
  bool get isAnyLoading =>
      _profileLoading ||
      _statsLoading ||
      _earningsLoading ||
      _ordersLoading ||
      _storeLoading;

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------

  /// Fans out the five parallel dashboard calls.
  ///
  /// Each call's result is captured independently so a single failed
  /// fetch leaves the other four cards populated (R5.3). Listeners are
  /// notified once after all five settle so the UI sees a single
  /// repaint instead of five intermediate states.
  ///
  /// Safe to call repeatedly: each invocation flips every card into
  /// loading, clears its previous error, and replaces the data on
  /// success.
  Future<void> refresh() async {
    _profileLoading = true;
    _statsLoading = true;
    _earningsLoading = true;
    _ordersLoading = true;
    _storeLoading = true;
    _profileError = null;
    _statsError = null;
    _earningsError = null;
    _ordersError = null;
    _storeError = null;
    notifyListeners();

    await Future.wait<void>(<Future<void>>[
      _refreshProfile(),
      _refreshStats(),
      _refreshEarningsToday(),
      _refreshOrders(),
      _refreshStore(),
    ]);

    notifyListeners();
  }

  /// Refreshes only the profile card (used by the per-card retry).
  Future<void> refreshProfile() async {
    await _refreshProfile();
    notifyListeners();
  }

  /// Refreshes only the stats card.
  Future<void> refreshStats() async {
    await _refreshStats();
    notifyListeners();
  }

  /// Refreshes only the today-earnings card.
  Future<void> refreshEarningsToday() async {
    await _refreshEarningsToday();
    notifyListeners();
  }

  /// Refreshes only the orders card.
  Future<void> refreshOrders() async {
    await _refreshOrders();
    notifyListeners();
  }

  /// Refreshes only the store-info card.
  Future<void> refreshStore() async {
    await _refreshStore();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _refreshProfile() async {
    _profileLoading = true;
    _profileError = null;
    try {
      _profile = await _api.getProfile();
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'HomeDashboardController.profile failed: $e',
        error: e,
        stackTrace: stack,
      );
      _profileError = e.toString();
    } finally {
      _profileLoading = false;
    }
  }

  Future<void> _refreshStats() async {
    _statsLoading = true;
    _statsError = null;
    try {
      _stats = await _api.getStats();
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'HomeDashboardController.stats failed: $e',
        error: e,
        stackTrace: stack,
      );
      _statsError = e.toString();
    } finally {
      _statsLoading = false;
    }
  }

  Future<void> _refreshEarningsToday() async {
    _earningsLoading = true;
    _earningsError = null;
    try {
      _earningsToday = await _api.getEarnings(EarningsPeriod.today);
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'HomeDashboardController.earningsToday failed: $e',
        error: e,
        stackTrace: stack,
      );
      _earningsError = e.toString();
    } finally {
      _earningsLoading = false;
    }
  }

  Future<void> _refreshOrders() async {
    _ordersLoading = true;
    _ordersError = null;
    try {
      _orders = await _api.getOrders();
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'HomeDashboardController.orders failed: $e',
        error: e,
        stackTrace: stack,
      );
      _ordersError = e.toString();
    } finally {
      _ordersLoading = false;
    }
  }

  Future<void> _refreshStore() async {
    _storeLoading = true;
    _storeError = null;
    try {
      _store = await _api.getStoreInfo();
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'HomeDashboardController.store failed: $e',
        error: e,
        stackTrace: stack,
      );
      _storeError = e.toString();
    } finally {
      _storeLoading = false;
    }
  }
}
