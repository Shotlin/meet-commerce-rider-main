import 'package:flutter/foundation.dart';

import '../../delivery/data/delivery_api.dart';
import '../../delivery/domain/delivery_history_entry.dart';

/// Manages paginated delivery history state.
///
/// Appends pages on [loadMore] calls. Callers should check [hasMore]
/// before calling [loadMore] to avoid redundant requests.
class HistoryController extends ChangeNotifier {
  /// Wires the controller to [DeliveryApi].
  HistoryController({required DeliveryApi api}) : _api = api;

  final DeliveryApi _api;

  static const int _kLimit = 20;

  /// Accumulated list of delivery history entries.
  List<DeliveryHistoryEntry> orders = <DeliveryHistoryEntry>[];

  /// Total number of orders on the server.
  int total = 0;

  /// Whether the first page is being fetched.
  bool isLoading = false;

  /// Whether a subsequent page is being fetched.
  bool isLoadingMore = false;

  /// Whether there are more pages to load.
  bool hasMore = true;

  /// Error message from the last failed fetch, or `null`.
  String? error;

  int _currentPage = 0;

  /// Loads the first page, resetting all state.
  Future<void> refresh() async {
    _currentPage = 0;
    orders = <DeliveryHistoryEntry>[];
    total = 0;
    hasMore = true;
    error = null;
    isLoading = true;
    notifyListeners();

    await _fetch(isFirst: true);
  }

  /// Appends the next page to [orders].
  ///
  /// No-ops when [isLoading], [isLoadingMore], or `!hasMore`.
  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore) return;
    isLoadingMore = true;
    error = null;
    notifyListeners();

    await _fetch(isFirst: false);
  }

  Future<void> _fetch({required bool isFirst}) async {
    try {
      final int nextPage = _currentPage + 1;
      final ({List<DeliveryHistoryEntry> orders, int total}) result = await _api
          .getHistory(page: nextPage, limit: _kLimit);

      if (isFirst) {
        orders = result.orders;
      } else {
        orders = <DeliveryHistoryEntry>[...orders, ...result.orders];
      }
      total = result.total;
      _currentPage = nextPage;

      // Determine if more pages exist.
      final int totalPages = (total / _kLimit).ceil();
      hasMore = _currentPage < totalPages;
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      isLoadingMore = false;
      notifyListeners();
    }
  }
}
