import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/location/location_permission_service.dart';
import '../../../core/location/location_permission_status.dart';
import '../../../core/maps/rider_maps_service.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------
const String _kNotifications = 'settings_notifications_enabled';
const String _kOrderAlerts = 'settings_order_alerts_enabled';
const String _kHighPrecision = 'settings_location_high_precision';

/// Local-only precision options for the location preference toggle.
enum _LocationPrecision {
  /// Default: rider profile picks the precision based on assignment state.
  auto,

  /// Always-high precision (heavier on battery).
  high,
}

/// Settings screen with notification preferences, help link, and an app
/// version footer.
///
/// Toggle state is persisted to [SharedPreferences] so selections survive
/// app restarts. Values are written on every change so no explicit
/// "Save" action is required.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Const constructor.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _orderAlertsEnabled = true;
  _LocationPrecision _precision = _LocationPrecision.auto;
  String _appVersion = '0.1.0 (1)';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadVersion();
  }

  Future<void> _loadPrefs() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = prefs.getBool(_kNotifications) ?? true;
        _orderAlertsEnabled = prefs.getBool(_kOrderAlerts) ?? true;
        _precision = (prefs.getBool(_kHighPrecision) ?? false)
            ? _LocationPrecision.high
            : _LocationPrecision.auto;
      });
    } catch (_) {
      // Fall back to in-memory defaults if SharedPreferences is unavailable.
    }
  }

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${info.version} (${info.buildNumber})';
        });
      }
    } catch (_) {
      // Keep the static fallback if PackageInfo fails.
    }
  }

  Future<void> _setNotifications(bool v) async {
    setState(() => _notificationsEnabled = v);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifications, v);
  }

  Future<void> _setOrderAlerts(bool v) async {
    setState(() => _orderAlertsEnabled = v);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOrderAlerts, v);
  }

  Future<void> _setPrecision(bool highEnabled) async {
    final _LocationPrecision next = highEnabled
        ? _LocationPrecision.high
        : _LocationPrecision.auto;
    setState(() => _precision = next);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHighPrecision, highEnabled);
  }

  @override
  Widget build(BuildContext context) {
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
          'Settings',
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
      ),
      // Preferences hydrate asynchronously, but the rows render with their
      // defaults immediately: a blocking spinner on a settings list adds no
      // value and (in tests) never settles. Nothing is persisted until the
      // rider actually flips a toggle, so there is no stale-write risk.
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const _SectionHeader(label: 'NOTIFICATIONS'),
          const SizedBox(height: 8),
          _ToggleRow(
            icon: Icons.notifications_outlined,
            label: 'Push notifications',
            value: _notificationsEnabled,
            onChanged: _setNotifications,
          ),
          const SizedBox(height: 8),
          _ToggleRow(
            icon: Icons.delivery_dining_outlined,
            label: 'Order alerts',
            value: _orderAlertsEnabled,
            onChanged: _setOrderAlerts,
          ),
          const SizedBox(height: 24),

          const _SectionHeader(label: 'LOCATION'),
          const SizedBox(height: 8),
          _ToggleRow(
            icon: Icons.gps_fixed,
            label: 'High-precision location',
            subtitle: _precision == _LocationPrecision.high
                ? 'Always high — heavier on battery'
                : 'Auto — battery friendly',
            value: _precision == _LocationPrecision.high,
            onChanged: _setPrecision,
          ),
          const SizedBox(height: 8),
          _LocationStatusRow(),
          const SizedBox(height: 24),

          const _SectionHeader(label: 'MAPS'),
          const SizedBox(height: 8),
          const _OlaMapsStatusRow(),
          const SizedBox(height: 24),

          const _SectionHeader(label: 'SUPPORT'),
          const SizedBox(height: 8),
          _TapRow(
            icon: Icons.help_outline,
            label: 'Help & support',
            // Big Phase 16: no support channel (phone/WhatsApp/email) is
            // configured in this environment yet — the dialog says so
            // honestly instead of pretending a channel exists.
            onTap: () => _showSupportDialog(context),
          ),
          const SizedBox(height: 24),

          const _SectionHeader(label: 'ABOUT'),
          const SizedBox(height: 8),
          _InfoTile(
            icon: Icons.info_outline,
            label: 'App version',
            value: _appVersion,
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Freashcut Rider · v$_appVersion',
              style: AppTypography.micro.copyWith(color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showSupportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          'Help & support',
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
        content: Text(
          'A dedicated support channel is not configured for this '
          'environment yet. For delivery issues, reach out to your '
          'FreshCuts store directly.',
          style: AppTypography.body.copyWith(color: AppColors.charcoal),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Live location-permission status (design §21 "location status") —
/// reads the real permission state via the service's read-only
/// [LocationPermissionService.check], never a guess.
class _LocationStatusRow extends ConsumerStatefulWidget {
  const _LocationStatusRow();

  @override
  ConsumerState<_LocationStatusRow> createState() => _LocationStatusRowState();
}

class _LocationStatusRowState extends ConsumerState<_LocationStatusRow> {
  LocationPermissionResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final LocationPermissionResult result = await ref
        .read<LocationPermissionService>(locationPermissionServiceProvider)
        .check();
    if (!mounted) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final LocationPermissionResult? result = _result;

    final (String label, IconData icon, Color color) = result == null
        ? ('Checking…', Icons.location_searching, AppColors.muted)
        : switch (result.permission) {
            LocationPermissionState.granted => (
              'Granted — while in use',
              Icons.check_circle_outline,
              AppColors.success,
            ),
            LocationPermissionState.deniedOnce => (
              'Not granted yet',
              Icons.error_outline,
              AppColors.warning,
            ),
            LocationPermissionState.deniedForever => (
              'Denied — enable in system settings',
              Icons.block_outlined,
              AppColors.danger,
            ),
            LocationPermissionState.restricted => (
              'Restricted by the system',
              Icons.block_outlined,
              AppColors.danger,
            ),
          };

    return _StatusRow(
      icon: icon,
      label: 'Location permission',
      value: label,
      valueColor: color,
    );
  }
}

/// Live Ola Maps status (design §21 "Ola Maps navigation status") —
/// reflects whether the backend has the key configured.
class _OlaMapsStatusRow extends ConsumerWidget {
  const _OlaMapsStatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<OlaMapsAvailability> availability = ref.watch(
      olaMapsAvailabilityProvider,
    );

    final (String label, IconData icon, Color color) = availability.maybeWhen(
      data: (OlaMapsAvailability a) => a.configured
          ? (
              'Configured — Ola vector maps',
              Icons.check_circle_outline,
              AppColors.success,
            )
          : (
              'Not configured for this environment',
              Icons.info_outline,
              AppColors.warning,
            ),
      orElse: () => ('Checking…', Icons.map_outlined, AppColors.muted),
    );

    return _StatusRow(
      icon: icon,
      label: 'Ola Maps',
      value: label,
      valueColor: color,
    );
  }
}

/// Shared status row shape for the settings status entries.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTypography.label.copyWith(color: AppColors.charcoal),
            ),
          ),
          Icon(Icons.circle, size: 8, color: valueColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              style: AppTypography.micro.copyWith(color: AppColors.muted),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets (unchanged API from previous version)
// ---------------------------------------------------------------------------

/// Section header label.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: AppTypography.micro.copyWith(color: AppColors.muted),
      ),
    );
  }
}

/// A toggle row for boolean settings.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.white,
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
                  style: AppTypography.body.copyWith(color: AppColors.charcoal),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTypography.micro.copyWith(color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.black,
          ),
        ],
      ),
    );
  }
}

/// A tappable row for navigation/action items.
class _TapRow extends StatelessWidget {
  const _TapRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
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
                child: Text(
                  label,
                  style: AppTypography.body.copyWith(color: AppColors.charcoal),
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

/// A non-tappable info row showing a label and value.
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 22, color: AppColors.charcoal),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTypography.body.copyWith(color: AppColors.charcoal),
            ),
          ),
          Text(
            value,
            style: AppTypography.body.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
