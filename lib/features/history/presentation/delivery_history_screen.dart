import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../delivery/domain/delivery_history_entry.dart';
import 'delivery_history_detail_sheet.dart';
import '../application/history_controller.dart';

/// Delivery history screen with infinite scroll.
///
/// Fetches typed [DeliveryHistoryEntry] records from
/// `GET /delivery/history` and displays each order with its number,
/// completion date, customer area, earnings, and status.
class DeliveryHistoryScreen extends ConsumerStatefulWidget {
  /// Const constructor.
  const DeliveryHistoryScreen({super.key});

  @override
  ConsumerState<DeliveryHistoryScreen> createState() =>
      _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends ConsumerState<DeliveryHistoryScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref.read<HistoryController>(historyControllerProvider).refresh(),
      );
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
        _scrollController.position.maxScrollExtent - 200) {
      unawaited(
        ref.read<HistoryController>(historyControllerProvider).loadMore(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final HistoryController controller = ref.watch<HistoryController>(
      historyControllerProvider,
    );
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
          'Delivery history',
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
      ),
      body: _buildBody(controller, commissionEnabled),
    );
  }

  Widget _buildBody(HistoryController controller, bool commissionEnabled) {
    if (controller.isLoading) {
      return const _HistorySkeleton();
    }

    if (controller.error != null && controller.orders.isEmpty) {
      return ErrorState(
        title: 'Could not load history',
        body: controller.error,
        onRetry: () => unawaited(
          ref.read<HistoryController>(historyControllerProvider).refresh(),
        ),
      );
    }

    if (controller.orders.isEmpty) {
      return const EmptyState(
        icon: Icons.delivery_dining_outlined,
        title: 'No deliveries yet',
        body: 'Your completed deliveries will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read<HistoryController>(historyControllerProvider).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount:
            controller.orders.length + (controller.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          if (index == controller.orders.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LoadingIndicator(),
            );
          }
          return _HistoryRow(
            entry: controller.orders[index],
            commissionEnabled: commissionEnabled,
          );
        },
      ),
    );
  }
}

/// A single delivery history row card.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.commissionEnabled});

  final DeliveryHistoryEntry entry;
  final bool commissionEnabled;

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

  String _orderNumber() {
    final String n = entry.orderNumber;
    if (n.isEmpty) return '—';
    if (n.length > 12) {
      return '#${n.substring(0, 12).toUpperCase()}';
    }
    return '#${n.toUpperCase()}';
  }

  StatusTone _toneFor(String status) {
    switch (status) {
      case 'DELIVERED':
        return StatusTone.success;
      case 'CANCELLED':
        return StatusTone.danger;
      default:
        return StatusTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showDeliveryHistoryDetailSheet(context, entry),
        child: Container(
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
                      _orderNumber(),
                      style: AppTypography.label.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.customerArea ?? 'Area unavailable',
                      style: AppTypography.body.copyWith(
                        color: AppColors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(entry.completedAt),
                      style: AppTypography.micro.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (commissionEnabled) ...<Widget>[
                    Text(
                      _money.format(entry.earnings),
                      style: AppTypography.heading.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  StatusChip(label: entry.status, tone: _toneFor(entry.status)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton placeholder for the first load.
class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, _) => Skeleton.box(height: 96),
    );
  }
}
