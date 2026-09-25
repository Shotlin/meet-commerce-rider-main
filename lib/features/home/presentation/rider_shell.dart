import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_offline_banner.dart';
import '../../earnings/presentation/earnings_screen.dart';
import '../../history/presentation/delivery_history_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import 'home_screen.dart';

/// Bottom-nav shell for the approved rider.
///
/// The four tabs (Home, Earnings, History, Profile) are stacked inside
/// an [IndexedStack] so each tab's scroll position and controller state
/// is preserved when the rider switches between them. Each tab loads
/// its own data the first time it's focused (the screens themselves
/// own their `initState` fetch logic).
///
/// The shell is what `/home` renders. The four tab routes
/// (`/earnings`, `/history`, `/profile`) are still registered in the
/// router so deep-links and the explicit profile-screen "Back" button
/// continue to work, but tapping the bottom nav switches the
/// IndexedStack rather than pushing a new route.
class RiderShell extends ConsumerStatefulWidget {
  /// Const constructor.
  const RiderShell({super.key});

  @override
  ConsumerState<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends ConsumerState<RiderShell> {
  /// Currently selected tab index.
  int _index = 0;

  /// Whether each tab has been focused at least once. Used to defer
  /// child construction until the rider visits the tab.
  final List<bool> _visited = <bool>[true, false, false, false];

  /// Cached children so each tab keeps its scroll/state when switched.
  late final List<Widget> _tabs = <Widget>[
    const HomeScreen(),
    const EarningsScreen(),
    const DeliveryHistoryScreen(),
    const ProfileScreen(),
  ];

  /// Empty placeholder shown for tabs the rider has not yet visited.
  static const Widget _placeholder = SizedBox.shrink();

  void _onTap(int next) {
    if (next == _index) return;
    setState(() {
      _index = next;
      _visited[next] = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(socketLifecycleManagerProvider);

    final bool isOffline =
        ref.watch<AsyncValue<bool>>(isOfflineStreamProvider).value ?? false;
    return Scaffold(
      backgroundColor: AppColors.white,
      body: AppOfflineBanner(
        isOffline: isOffline,
        child: IndexedStack(
          index: _index,
          children: <Widget>[
            for (int i = 0; i < _tabs.length; i++)
              _visited[i] ? _tabs[i] : _placeholder,
          ],
        ),
      ),
      bottomNavigationBar: _RiderBottomNav(currentIndex: _index, onTap: _onTap),
    );
  }
}

/// Bottom-nav bar styled per the rider design system.
class _RiderBottomNav extends StatelessWidget {
  const _RiderBottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
                isActive: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.account_balance_wallet_outlined,
                activeIcon: Icons.account_balance_wallet,
                label: 'Earnings',
                isActive: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                label: 'History',
                isActive: currentIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                isActive: currentIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single tab button inside the bottom navigation bar.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = isActive ? AppColors.charcoal : AppColors.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(isActive ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(label, style: AppTypography.micro.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
