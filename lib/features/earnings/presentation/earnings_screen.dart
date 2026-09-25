import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../delivery/data/delivery_api.dart';
import '../../../shared/widgets/app_button.dart';
import '../../delivery/domain/collections_summary.dart';
import '../../delivery/domain/rider_earnings.dart';
import '../application/earnings_controller.dart';

/// Available earnings periods rendered as chips.
const List<_PeriodOption> _kPeriods = <_PeriodOption>[
  _PeriodOption(key: EarningsPeriod.today, label: 'Today'),
  _PeriodOption(key: EarningsPeriod.week, label: 'Week'),
  _PeriodOption(key: EarningsPeriod.month, label: 'Month'),
  _PeriodOption(key: EarningsPeriod.all, label: 'All'),
];

class _PeriodOption {
  const _PeriodOption({required this.key, required this.label});
  final EarningsPeriod key;
  final String label;
}

/// Earnings screen showing period-based earnings breakdown.
///
/// Displays the period total, delivery count, and breakdown cards
/// (base fees, distance bonus, performance bonus, tips). The screen
/// lazily fetches each period on first selection through
/// [EarningsController].
class EarningsScreen extends ConsumerStatefulWidget {
  /// Const constructor.
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  EarningsPeriod _selectedPeriod = EarningsPeriod.today;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref
            .read<EarningsController>(earningsControllerProvider)
            .loadPeriod(_selectedPeriod),
      );
    });
  }

  void _selectPeriod(EarningsPeriod period) {
    if (_selectedPeriod == period) return;
    setState(() => _selectedPeriod = period);
    unawaited(
      ref
          .read<EarningsController>(earningsControllerProvider)
          .loadPeriod(period),
    );
  }

  @override
  Widget build(BuildContext context) {
    final EarningsController controller = ref.watch<EarningsController>(
      earningsControllerProvider,
    );
    final bool loading = controller.isLoading(_selectedPeriod);
    final String? errorMsg = controller.error(_selectedPeriod);
    final RiderEarnings? earnings = controller.dataFor(_selectedPeriod);
    final bool commissionEnabled =
        ref.watch(riderProfileProvider).asData?.value.commissionEnabled ?? true;

    if (!commissionEnabled) {
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
            'Earnings',
            style: AppTypography.heading.copyWith(color: AppColors.charcoal),
          ),
        ),
        body: const EmptyState(
          icon: Icons.badge_outlined,
          title: 'You\'re on a fixed salary',
          body:
              'Commission-based earnings are currently paused. '
              'Your pay is handled outside the app.',
        ),
      );
    }

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
          'Earnings',
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.receipt_long, color: AppColors.charcoal),
            tooltip: 'Payout history',
            onPressed: () => context.push(AppRoutes.payoutHistory),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _PeriodChipBar(selected: _selectedPeriod, onSelect: _selectPeriod),
          Expanded(child: _buildContent(loading, errorMsg, earnings)),
        ],
      ),
    );
  }

  Widget _buildContent(
    bool loading,
    String? errorMsg,
    RiderEarnings? earnings,
  ) {
    if (loading && earnings == null) {
      return const _EarningsSkeleton();
    }
    if (errorMsg != null && earnings == null) {
      return ErrorState(
        title: 'Could not load earnings',
        body: errorMsg,
        onRetry: () => unawaited(
          ref
              .read<EarningsController>(earningsControllerProvider)
              .loadPeriod(_selectedPeriod, forceRefresh: true),
        ),
      );
    }
    if (earnings == null ||
        (earnings.totalEarnings == 0 && earnings.deliveriesCount == 0)) {
      return const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No earnings yet',
        body: 'Complete deliveries to start earning.',
      );
    }
    return _EarningsContent(earnings: earnings);
  }
}

/// Period selector chip bar.
class _PeriodChipBar extends StatelessWidget {
  const _PeriodChipBar({required this.selected, required this.onSelect});

  final EarningsPeriod selected;
  final ValueChanged<EarningsPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: _kPeriods.map((_PeriodOption opt) {
          final bool isSelected = opt.key == selected;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onSelect(opt.key),
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.easing,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.black : AppColors.offWhite,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    opt.label,
                    style: AppTypography.label.copyWith(
                      color: isSelected ? AppColors.white : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Main earnings content when data is available.
class _EarningsContent extends ConsumerWidget {
  const _EarningsContent({required this.earnings});

  final RiderEarnings earnings;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CollectionsSummary? collectionsSummary = ref
        .watch(homeDashboardControllerProvider)
        .collections;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Hero total earnings card (design §17: white card, brand-red
          // amount — not the seed's black hero).
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'TOTAL EARNINGS',
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Text(
                  _money.format(earnings.totalEarnings),
                  style: AppTypography.display.copyWith(color: AppColors.brand),
                ),
                const SizedBox(height: 8),
                Text(
                  '${earnings.deliveriesCount} '
                  '${earnings.deliveriesCount == 1 ? 'delivery' : 'deliveries'}',
                  style: AppTypography.body.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Breakdown section (only components the backend returns —
          // requirement §17: "only show components actually returned").
          Text(
            'BREAKDOWN',
            style: AppTypography.micro.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: <Widget>[
              StatCard(
                label: 'Base fees',
                value: _money.format(earnings.breakdown.baseDeliveryFees),
                icon: Icons.local_shipping_outlined,
              ),
              StatCard(
                label: 'Distance bonus',
                value: _money.format(earnings.breakdown.distanceBonus),
                icon: Icons.route_outlined,
                accent: AppColors.mapBlue,
              ),
              StatCard(
                label: 'Performance',
                value: _money.format(earnings.breakdown.performanceBonus),
                icon: Icons.star_outline,
                accent: AppColors.warning,
              ),
              StatCard(
                label: 'Tips',
                value: _money.format(earnings.breakdown.tips),
                icon: Icons.volunteer_activism_outlined,
                accent: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // COD collections snapshot (Big Phase 14 ledger) — the cash
          // side of the rider's money, next to the commission side.
          Text(
            'CASH COLLECTIONS',
            style: AppTypography.micro.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          _CollectionsStrip(summary: collectionsSummary),
          const SizedBox(height: 16),

          // Payout section
          Text(
            'PAYOUTS',
            style: AppTypography.micro.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: StatCard(
                  label: 'Pending payout',
                  value: _money.format(earnings.pendingPayout),
                  icon: Icons.pending_outlined,
                  accent: AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Last payout',
                  value: _money.format(earnings.lastPayoutAmount),
                  icon: Icons.check_circle_outline,
                  accent: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'View payout history',
            variant: AppButtonVariant.secondary,
            onPressed: () => unawaited(context.push(AppRoutes.payoutHistory)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Skeleton placeholder while earnings are loading.
class _EarningsSkeleton extends StatelessWidget {
  const _EarningsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Skeleton.box(height: 140, radius: 20),
          const SizedBox(height: 16),
          Skeleton.line(height: 12, width: 80),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: List<Widget>.generate(4, (_) => Skeleton.box(height: 80)),
          ),
          const SizedBox(height: 16),
          Skeleton.line(height: 12, width: 60),
          const SizedBox(height: 8),
          Skeleton.box(height: 72),
          const SizedBox(height: 12),
          Skeleton.box(height: 72),
        ],
      ),
    );
  }
}

/// Compact cash-collections snapshot (Big Phase 14): the cash side of
/// the rider's money, next to the commission side. Values come from
/// `/delivery/collections/summary`; zeros when nothing collected yet.
class _CollectionsStrip extends StatelessWidget {
  const _CollectionsStrip({required this.summary});

  final CollectionsSummary? summary;

  @override
  Widget build(BuildContext context) {
    final CollectionsSummary? s = summary;
    if (s == null ||
        (s.collectedToday == 0 &&
            s.cashInHand == 0 &&
            s.upiCollectedTotal == 0)) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'No COD collections yet. Cash you collect on delivery appears here.',
          style: AppTypography.micro.copyWith(color: AppColors.muted),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Collected today',
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  _CollectionsStripX.money(s.collectedToday),
                  style: AppTypography.label.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Cash in hand',
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  _CollectionsStripX.money(s.cashInHand),
                  style: AppTypography.label.copyWith(color: AppColors.warning),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'UPI collected',
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  _CollectionsStripX.money(s.upiCollectedTotal),
                  style: AppTypography.label.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _CollectionsStripX on Object {
  static String money(double value) =>
      '₹${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}';
}
