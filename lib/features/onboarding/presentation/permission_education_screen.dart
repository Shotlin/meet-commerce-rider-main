import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_permission_service.dart';
import '../../../core/location/location_permission_status.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';

/// Permission education screen shown when the rider needs to grant
/// location permission before going online (R6.3, R29.1).
///
/// Premium minimal design: white surface, charcoal copy, primary black
/// CTA, optional secondary CTA when the permission has been permanently
/// denied.
///
/// Behaviour:
/// - The "Allow location" CTA calls
///   [LocationPermissionService.ensureWhileInUse]. When the resulting
///   [LocationPermissionResult.canUseLocation] is `true` (or the rider has
///   permanently denied the prompt), the screen pops with the result so
///   the caller can decide what to do next (proceed online, route to
///   settings, or stay on the home screen).
/// - The "Open settings" CTA only renders when the latest result reports
///   [LocationPermissionState.deniedForever]. It calls
///   [LocationPermissionService.openAppSettings]; the rider returns to
///   the screen after granting permission and can re-tap "Allow
///   location" to refresh the state.
class PermissionEducationScreen extends ConsumerStatefulWidget {
  /// Const constructor so routes can use `const PermissionEducationScreen()`.
  const PermissionEducationScreen({super.key});

  @override
  ConsumerState<PermissionEducationScreen> createState() =>
      _PermissionEducationScreenState();
}

class _PermissionEducationScreenState
    extends ConsumerState<PermissionEducationScreen> {
  /// Tracks the most recent permission result so the UI can decide
  /// whether to reveal the "Open settings" affordance.
  LocationPermissionResult? _lastResult;

  /// True while a port call is in flight; disables both CTAs.
  bool _busy = false;

  Future<void> _onAllowLocation() async {
    if (_busy) return;
    setState(() => _busy = true);

    final LocationPermissionService service = ref
        .read<LocationPermissionService>(locationPermissionServiceProvider);

    final LocationPermissionResult result = await service.ensureWhileInUse();

    if (!mounted) return;
    setState(() {
      _lastResult = result;
      _busy = false;
    });

    if (result.canUseLocation) {
      Navigator.of(context).pop<LocationPermissionResult>(result);
    }
    // Otherwise: stay on screen so the rider can either retry or open
    // settings. The "Open settings" button will appear automatically
    // when the latest result is deniedForever.
  }

  Future<void> _onOpenSettings() async {
    if (_busy) return;
    setState(() => _busy = true);

    final LocationPermissionService service = ref
        .read<LocationPermissionService>(locationPermissionServiceProvider);

    await service.openAppSettings();

    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool showOpenSettings =
        _lastResult != null &&
        _lastResult!.permission == LocationPermissionState.deniedForever;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.charcoal),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 16),

              // Hero icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  size: 32,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Location keeps you online',
                style: AppTypography.title.copyWith(color: AppColors.charcoal),
              ),
              const SizedBox(height: 12),

              // Body copy (R6.3, R29.1)
              Text(
                "Freashcut Rider needs your location while you're on shift to "
                "deliver orders to customers. We only collect location while "
                "the app is open and you're online.",
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),

              const Spacer(),

              // Inline status hint when the user has permanently denied.
              if (showOpenSettings) ...<Widget>[
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Location permission is turned off. Open settings '
                          'to allow location access for Freashcut Rider.',
                          style: AppTypography.micro.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Primary CTA
              AppButton(
                label: 'Allow location',
                isLoading: _busy,
                onPressed: _busy ? null : _onAllowLocation,
              ),
              if (showOpenSettings) ...<Widget>[
                const SizedBox(height: 12),
                AppButton(
                  label: 'Open settings',
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : _onOpenSettings,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
