import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../auth/application/session_controller.dart';
import '../../delivery/domain/rider_profile.dart';

/// Profile screen showing rider details and navigation to sub-screens.
///
/// Renders the typed [RiderProfile] returned by `GET /delivery/profile`
/// (the snake_case + string-typed numerics are normalised by the
/// model's parser, so the screen consumes plain Dart fields).
///
/// Wires:
/// - Documents CTA → re-entry into the approval / upload flow.
/// - Settings link → settings screen.
/// - Logout → clears session and routes back to login.
class ProfileScreen extends ConsumerWidget {
  /// Const constructor.
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RiderProfile> profileAsync = ref.watch(
      riderProfileProvider,
    );

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
          'Profile',
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.charcoal),
            tooltip: 'Edit profile',
            onPressed: () => context.push(AppRoutes.editProfile),
          ),
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.charcoal,
            ),
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const _ProfileSkeleton(),
        error: (Object err, StackTrace _) => ErrorState(
          title: 'Could not load profile',
          body: err.toString(),
          onRetry: () => ref.invalidate(riderProfileProvider),
        ),
        data: (RiderProfile profile) => _ProfileContent(profile: profile),
      ),
    );
  }
}

/// Profile content when data is available.
class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({required this.profile});

  final RiderProfile profile;

  /// Returns the rider's phone in `+91 XXXXXXXXXX` form. The live
  /// backend stores 10-digit numbers without the country code, so the
  /// `+91` prefix is added back here for display.
  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '—';
    final String digits = phone.replaceAll(RegExp(r'^\+?91'), '').trim();
    if (digits.isEmpty) return '+91';
    return '+91 $digits';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Avatar + name header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: <Widget>[
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.offWhite,
                  backgroundImage: profile.avatarUrl != null
                      ? NetworkImage(profile.avatarUrl!)
                      : null,
                  child: profile.avatarUrl == null
                      ? const Icon(
                          Icons.person,
                          size: 36,
                          color: AppColors.muted,
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  profile.name?.isNotEmpty == true ? profile.name! : 'Rider',
                  style: AppTypography.title.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatPhone(profile.phone),
                  style: AppTypography.body.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: <Widget>[
              Expanded(
                child: _StatTile(
                  label: 'Rating',
                  value: profile.rating.toStringAsFixed(1),
                  icon: Icons.star_rounded,
                  iconColor: AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'Deliveries',
                  value: profile.totalDeliveries.toString(),
                  icon: Icons.delivery_dining,
                  iconColor: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Vehicle info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'VEHICLE',
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Type',
                  value: profile.vehicleType ?? 'Not set',
                ),
                const Divider(height: 24, color: AppColors.border),
                _InfoRow(
                  label: 'Number',
                  value: profile.vehicleNumber ?? 'Not set',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Navigation rows
          _NavRow(
            icon: Icons.description_outlined,
            label: 'Documents',
            subtitle: profile.isApproved ? 'Approved' : 'Re-enter or update',
            onTap: () => context.push(AppRoutes.approval),
          ),
          const SizedBox(height: 8),
          _NavRow(
            icon: Icons.history,
            label: 'Delivery history',
            subtitle: 'All your past orders',
            onTap: () => context.push(AppRoutes.history),
          ),
          const SizedBox(height: 8),
          // Payout history is per-order earnings — meaningless for a
          // salaried rider (no commission), so only surfaced when there's
          // actually commission to show a history of.
          if (profile.commissionEnabled) ...<Widget>[
            _NavRow(
              icon: Icons.payments_outlined,
              label: 'Payout history',
              subtitle: 'Your commission payouts',
              onTap: () => context.push(AppRoutes.payoutHistory),
            ),
            const SizedBox(height: 8),
          ],
          _NavRow(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(height: 24),

          // Logout button
          AppButton(
            label: 'Log out',
            variant: AppButtonVariant.danger,
            onPressed: () async {
              await ref
                  .read<SessionController>(sessionControllerProvider)
                  .logout();
              if (!context.mounted) return;
              context.go(AppRoutes.login);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// A small stat tile used in the profile stats row.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

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
        children: <Widget>[
          Icon(icon, size: 24, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: AppTypography.heading.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
                Text(
                  label,
                  style: AppTypography.micro.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A key-value info row.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: AppTypography.body.copyWith(color: AppColors.muted)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.body.copyWith(color: AppColors.charcoal),
          ),
        ),
      ],
    );
  }
}

/// A tappable navigation row.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 22, color: AppColors.charcoal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      style: AppTypography.body.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppTypography.micro.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton placeholder while profile is loading.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Skeleton.box(height: 160, radius: 20),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: Skeleton.box(height: 80)),
              const SizedBox(width: 12),
              Expanded(child: Skeleton.box(height: 80)),
            ],
          ),
          const SizedBox(height: 16),
          Skeleton.box(height: 100),
          const SizedBox(height: 16),
          Skeleton.box(height: 56),
          const SizedBox(height: 8),
          Skeleton.box(height: 56),
          const SizedBox(height: 24),
          Skeleton.box(height: 52),
        ],
      ),
    );
  }
}
