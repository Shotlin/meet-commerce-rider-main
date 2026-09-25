import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/config/app_constants.dart';
import '../../../core/config/env.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/brand_mark.dart';
import '../application/auth_controller.dart';
import '../application/auth_state.dart';

/// Seed rider credentials shown in the demo quick-login card.
const String _demoPhone = '9000000001';
const String _demoOtp = '123456';

/// Phone login screen — first step of the OTP flow.
///
/// Design decisions:
/// - The +91 country code is a fixed prefix badge inside the field;
///   the rider only types the 10-digit number.
/// - Input is hard-capped at 10 digits; non-digit characters are
///   stripped on every keystroke.
/// - A "Demo login" card (dev builds only) auto-fills the seed number
///   and fires Send OTP with a single tap.
class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Tracks whether the field has focus for border styling.
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _hasFocus = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _onSendOtp() async {
    FocusScope.of(context).unfocus();
    final String digits = _digitsOnly(_controller.text);
    if (digits.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit mobile number')),
      );
      return;
    }
    final AuthController auth = ref.read<AuthController>(
      authControllerProvider,
    );
    final bool ok = await auth.sendOtp(digits);
    if (!mounted) return;
    if (ok) context.go(AppRoutes.otp);
  }

  /// One-tap demo login: fill the seed number and immediately send OTP.
  Future<void> _onDemoLogin() async {
    FocusScope.of(context).unfocus();
    _controller.text = _demoPhone;
    // Small delay so the user sees the number appear before the spinner.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _onSendOtp();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Strips everything except digits and caps at 10 characters.
  static String _digitsOnly(String raw) {
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 10 ? digits.substring(0, 10) : digits;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AuthState state = ref
        .watch<AuthController>(authControllerProvider)
        .state;
    final Env env = ref.watch<Env>(envProvider);
    final bool busy = state.isBusy;
    final bool hasError = state.errorMessage != null;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 56),

                  // ── Brand header (design §7: minimal logo/header) ──────
                  const BrandMark(size: AppDimensions.brandMarkSmall),
                  const SizedBox(height: AppDimensions.lg),

                  // ── Hero copy ──────────────────────────────────────────
                  const Text('Welcome, Rider', style: AppTypography.display),
                  const SizedBox(height: AppDimensions.sm),
                  Text(
                    'Log in to start accepting FreshCuts deliveries.',
                    style: AppTypography.body.copyWith(color: AppColors.muted),
                  ),

                  const SizedBox(height: 48),

                  // ── Phone field label ──────────────────────────────────
                  Text(
                    'Mobile number',
                    style: AppTypography.label.copyWith(
                      color: AppColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.sm),

                  // ── Phone input with +91 prefix ────────────────────────
                  _PhoneField(
                    controller: _controller,
                    focusNode: _focusNode,
                    hasFocus: _hasFocus,
                    hasError: hasError,
                    errorText: state.errorMessage,
                    enabled: !busy,
                    onSubmitted: (_) => _onSendOtp(),
                  ),

                  const SizedBox(height: AppDimensions.xxl),

                  // ── Continue button (design §7: red CTA) ───────────────
                  AppButton(
                    label: 'Continue',
                    isLoading: state.phase == AuthPhase.sendingOtp,
                    onPressed: busy ? null : _onSendOtp,
                  ),

                  const SizedBox(height: AppDimensions.md),
                  Text(
                    AppConstants.loginTrustCopy,
                    textAlign: TextAlign.center,
                    style: AppTypography.micro.copyWith(color: AppColors.muted),
                  ),

                  const Spacer(),

                  // ── Demo quick-login (dev builds only) ─────────────────
                  if (env.enableDevAffordances) ...<Widget>[
                    const SizedBox(height: 32),
                    _DemoLoginCard(busy: busy, onTap: _onDemoLogin),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone field — fixed +91 prefix + 10-digit-only input
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.focusNode,
    required this.hasFocus,
    required this.hasError,
    required this.enabled,
    required this.onSubmitted,
    this.errorText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasFocus;
  final bool hasError;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = hasError
        ? AppColors.danger
        : hasFocus
        ? AppColors.charcoal
        : AppColors.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: AppColors.offWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: <Widget>[
              // Fixed +91 prefix
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: borderColor)),
                ),
                child: Text(
                  '+91',
                  style: AppTypography.body.copyWith(color: AppColors.charcoal),
                ),
              ),
              // 10-digit input
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  enabled: enabled,
                  style: AppTypography.body,
                  cursorColor: AppColors.charcoal,
                  onSubmitted: onSubmitted,
                  // Strip non-digits and cap at 10 characters
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    hintText: '98765 43210',
                    hintStyle: AppTypography.body.copyWith(
                      color: AppColors.muted,
                    ),
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (errorText != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: AppTypography.micro.copyWith(color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Demo quick-login card (dev builds only)
// ─────────────────────────────────────────────────────────────────────────────

class _DemoLoginCard extends StatelessWidget {
  const _DemoLoginCard({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Section label
        Row(
          children: <Widget>[
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'DEMO',
                style: AppTypography.micro.copyWith(color: AppColors.muted),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),

        // Quick-login tile
        Material(
          color: AppColors.offWhite,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: busy ? null : onTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.black,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: AppColors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Login as demo rider',
                          style: AppTypography.label.copyWith(
                            color: AppColors.charcoal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '+91 $_demoPhone  ·  OTP: $_demoOtp',
                          style: AppTypography.micro.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.muted,
                        ),
                      ),
                    )
                  else
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: AppColors.muted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
