import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_envelope.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../delivery/data/delivery_api.dart';
import '../../delivery/domain/payout.dart';

/// Immutable view-model for the payout history screen.
class _PayoutHistoryState {
  const _PayoutHistoryState({
    this.items = const <Payout>[],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.currentPage = 0,
  });

  final List<Payout> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int currentPage;

  _PayoutHistoryState copyWith({
    List<Payout>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? currentPage,
  }) {
    return _PayoutHistoryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

/// Payout history screen with infinite scroll pagination.
///
/// Fetches payout records from `GET /delivery/payouts` (typed
/// [DeliveryApi.getPayouts] returning a typed record of `items` and
/// `pagination`) and displays them in a scrollable list. Loads the
/// next page when the user scrolls to the bottom.
class PayoutHistoryScreen extends ConsumerStatefulWidget {
  /// Const constructor.
  const PayoutHistoryScreen({super.key});

  @override
  ConsumerState<PayoutHistoryScreen> createState() =>
      _PayoutHistoryScreenState();
}

class _PayoutHistoryScreenState extends ConsumerState<PayoutHistoryScreen> {
  _PayoutHistoryState _state = const _PayoutHistoryState();
  final ScrollController _scrollController = ScrollController();

  static const int _kLimit = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadFirst());
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_state.isLoadingMore &&
        _state.hasMore) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadFirst() async {
    setState(() {
      _state = const _PayoutHistoryState(isLoading: true);
    });
    await _fetchPage(1, isFirst: true);
  }

  Future<void> _loadMore() async {
    if (_state.isLoadingMore || !_state.hasMore) return;
    setState(() {
      _state = _state.copyWith(isLoadingMore: true);
    });
    await _fetchPage(_state.currentPage + 1, isFirst: false);
  }

  Future<void> _fetchPage(int page, {required bool isFirst}) async {
    try {
      final DeliveryApi api = ref.read<DeliveryApi>(deliveryApiProvider);
      final ({List<Payout> items, Pagination pagination}) result = await api
          .getPayouts(page: page, limit: _kLimit);

      final List<Payout> newItems = isFirst
          ? result.items
          : <Payout>[..._state.items, ...result.items];

      final bool hasMore =
          result.pagination.page < result.pagination.totalPages;

      if (!mounted) return;
      setState(() {
        _state = _PayoutHistoryState(
          items: newItems,
          hasMore: hasMore,
          currentPage: result.pagination.page,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _state.copyWith(error: e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool commissionEnabled =
        ref.watch(riderProfileProvider).asData?.value.commissionEnabled ?? true;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.charcoal),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Payout history',
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
      ),
      body: Column(
        children: <Widget>[
          // Item 10: past payouts are real, already-paid money and stay
          // visible regardless of the flag — only new commission
          // accrual is disabled. This banner just explains why the
          // list may have stopped growing.
          if (!commissionEnabled)
            Container(
              width: double.infinity,
              color: AppColors.offWhite,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(
                'Commission is currently paused — you\'re on a fixed '
                'salary. Past payouts remain below.',
                style: AppTypography.micro.copyWith(color: AppColors.muted),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_state.isLoading) {
      return const _PayoutSkeleton();
    }

    if (_state.error != null && _state.items.isEmpty) {
      return ErrorState(
        title: 'Could not load payouts',
        body: _state.error,
        onRetry: () => unawaited(_loadFirst()),
      );
    }

    if (_state.items.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No payouts yet',
        body: 'Your payout history will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _state.items.length + (_state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          if (index == _state.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LoadingIndicator(),
            );
          }
          return _PayoutRow(payout: _state.items[index]);
        },
      ),
    );
  }
}

/// A single payout row card.
class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout});

  final Payout payout;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final DateFormat _date = DateFormat('d MMM yyyy');

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return _date.format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  String _truncatedId(String id) {
    if (id.length <= 8) return id.toUpperCase();
    return id.substring(0, 8).toUpperCase();
  }

  StatusTone _toneFor(String status) {
    switch (status) {
      case 'PAID':
      case 'COMPLETED':
        return StatusTone.success;
      case 'PENDING':
      case 'PROCESSING':
        return StatusTone.pending;
      case 'FAILED':
        return StatusTone.danger;
      default:
        return StatusTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _money.format(payout.amount),
                  style: AppTypography.heading.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(payout.createdAt),
                  style: AppTypography.body.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  '#${_truncatedId(payout.id)}',
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          StatusChip(label: payout.status, tone: _toneFor(payout.status)),
        ],
      ),
    );
  }
}

/// Skeleton placeholder for the first load.
class _PayoutSkeleton extends StatelessWidget {
  const _PayoutSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, _) => Skeleton.box(height: 88),
    );
  }
}
