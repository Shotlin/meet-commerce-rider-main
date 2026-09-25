import 'package:flutter/foundation.dart';

import '../../delivery/data/delivery_api.dart';
import '../../delivery/domain/rider_earnings.dart';

/// Manages earnings data per period, caching fetched results.
///
/// Holds a [Map] keyed by the typed [EarningsPeriod]. Each period is
/// fetched lazily on first [loadPeriod] call and cached thereafter.
/// Callers can force a refresh by calling [loadPeriod] again with
/// [forceRefresh] set to `true`.
class EarningsController extends ChangeNotifier {
  /// Wires the controller to [DeliveryApi].
  EarningsController({required DeliveryApi api}) : _api = api;

  final DeliveryApi _api;

  final Map<EarningsPeriod, RiderEarnings?> _data =
      <EarningsPeriod, RiderEarnings?>{};
  final Map<EarningsPeriod, bool> _loading = <EarningsPeriod, bool>{};
  final Map<EarningsPeriod, String?> _errors = <EarningsPeriod, String?>{};

  /// Returns the cached [RiderEarnings] for [period], or `null` if not
  /// yet loaded.
  RiderEarnings? dataFor(EarningsPeriod period) => _data[period];

  /// Returns `true` while [period] is being fetched.
  bool isLoading(EarningsPeriod period) => _loading[period] ?? false;

  /// Returns the error message for [period], or `null` if no error.
  String? error(EarningsPeriod period) => _errors[period];

  /// Fetches and caches earnings for [period].
  ///
  /// Skips the network call if data is already cached and
  /// [forceRefresh] is `false`.
  Future<void> loadPeriod(
    EarningsPeriod period, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _data.containsKey(period)) return;
    _loading[period] = true;
    _errors[period] = null;
    notifyListeners();

    try {
      final RiderEarnings earnings = await _api.getEarnings(period);
      _data[period] = earnings;
      _errors[period] = null;
    } catch (e) {
      _errors[period] = e.toString();
      _data[period] = null;
    } finally {
      _loading[period] = false;
      notifyListeners();
    }
  }
}
