import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../app/router.dart';
import '../../../core/config/app_constants.dart';
import '../../../core/config/env.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';
import '../application/auth_controller.dart';
import '../application/auth_state.dart';

/// OTP entry screen.
///
/// Renders a single 6-digit input bound to a single `TextField`
/// (rather than per-digit boxes) to keep accessibility, paste support,
/// and platform autofill working out of the box. The premium minimal
/// look comes from the input style and the full-width black CTA.
class OtpScreen extends ConsumerStatefulWidget {
  /// Const constructor so the route can use `const OtpScreen()`.
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Auto-fill the dev OTP whenever the controller surfaces one in dev
    // builds, and refresh the resend countdown every second.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _maybePrefillDevOtp();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _maybePrefillDevOtp() {
    final Env env = ref.read<Env>(envProvider);
    if (!env.enableDevAffordances) return;
    final String? otp = ref
        .read<AuthController>(authControllerProvider)
        .state
        .devOtp;
    if (otp != null &&
        otp.length == AppConstants.loginOtpLength &&
        _controller.text.isEmpty) {
      _controller.text = otp;
    }
  }

  Future<void> _onVerify() async {
    FocusScope.of(context).unfocus();
    final String value = _controller.text.trim();
    if (value.length != AppConstants.loginOtpLength) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter the 6-digit OTP')));
      return;
    }
    final AuthController auth = ref.read<AuthController>(
      authControllerProvider,
    );
    final result = await auth.verifyOtp(value);
    if (!mounted) return;
    if (result != null) {
      // Router redirect handles destination; just leave the OTP screen.
      context.go(AppRoutes.splash);
    }
  }

  Future<void> _onResend() async {
    final AuthController auth = ref.read<AuthController>(
      authControllerProvider,
    );
    if (!auth.canResend()) return;
    await auth.resendOtp();
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = ref.watch<AuthController>(
      authControllerProvider,
    );
    final AuthState state = auth.state;
    final Env env = ref.watch<Env>(envProvider);

    final int remaining = auth.resendSecondsRemaining();
    final bool canResend = auth.canResend();
    final bool busy = state.isBusy;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            auth.reset();
            context.go(AppRoutes.login);
          },
        ),
        title: const Text('Verify number'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8),
              Text(
                state.phone == null
                    ? 'Enter the OTP we just sent'
                    : 'Enter the OTP sent to ${state.phone}',
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 24),
              _OtpInputField(
                controller: _controller,
                focus: _focus,
                onSubmitted: (_) => _onVerify(),
                errorText: state.errorMessage,
              ),
              const SizedBox(height: 16),
              if (env.enableDevAffordances && state.devOtp != null)
                _DevOtpHint(otp: state.devOtp!),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    canResend
                        ? "Didn't get the OTP?"
                        : 'Resend OTP in ${remaining}s',
                    style: AppTypography.label.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(width: 4),
                  if (canResend)
                    TextButton(
                      onPressed: busy ? null : _onResend,
                      child: const Text('Resend'),
                    ),
                ],
              ),
              const Spacer(),
              AppButton(
                label: 'Verify',
                isLoading: state.phase == AuthPhase.verifyingOtp,
                onPressed: busy ? null : _onVerify,
              ),
              // Editable phone link (design §7): the rider can correct a
              // mistyped number without any hidden navigation.
              const SizedBox(height: AppDimensions.sm),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        auth.reset();
                        context.go(AppRoutes.login);
                      },
                child: const Text('Wrong number? Change it'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visual treatment for the OTP input (design §7: "6-digit input with large
/// cells", errors immediately below the field).
///
/// A single [TextField] remains the source of truth — paste, platform OTP
/// autofill and screen readers all keep working — but it is rendered
/// transparently *on top of* six large visual cells that display the entered
/// digits. The focused cell gets a brand-coloured border, so the rider always
/// sees where the next digit lands.
class _OtpInputField extends StatelessWidget {
  const _OtpInputField({
    required this.controller,
    required this.focus,
    required this.onSubmitted,
    this.errorText,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onSubmitted;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GestureDetector(
          // Tapping anywhere in the row focuses the (invisible) field.
          onTap: () => focus.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: <Widget>[
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (BuildContext context, TextEditingValue value, _) {
                  final String digits = value.text;
                  final bool focused = focus.hasFocus;
                  return Row(
                    children: <Widget>[
                      for (int i = 0; i < AppConstants.loginOtpLength; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: i == AppConstants.loginOtpLength - 1
                                  ? 0
                                  : AppDimensions.sm,
                            ),
                            child: _OtpCell(
                              digit: i < digits.length ? digits[i] : '',
                              isActive: focused && i == digits.length,
                              hasError: errorText != null,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              Positioned.fill(
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  showCursor: false,
                  maxLength: AppConstants.loginOtpLength,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(
                      AppConstants.loginOtpLength,
                    ),
                  ],
                  // The cells render the digits; this surface only captures
                  // input, so nothing it paints may be visible.
                  style: const TextStyle(color: Color(0x00000000)),
                  cursorColor: const Color(0x00000000),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: onSubmitted,
                ),
              ),
            ],
          ),
        ),
        if (errorText != null) ...<Widget>[
          const SizedBox(height: AppDimensions.sm),
          Text(
            errorText!,
            style: AppTypography.micro.copyWith(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// One large OTP cell.
class _OtpCell extends StatelessWidget {
  const _OtpCell({
    required this.digit,
    required this.isActive,
    required this.hasError,
  });

  /// Digit to render, or an empty string for a not-yet-entered cell.
  final String digit;

  /// Whether this is the next cell to be filled (brand-coloured outline).
  final bool isActive;

  /// Whether the whole field is in an error state.
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = hasError
        ? AppColors.danger
        : isActive
        ? AppColors.brand
        : AppColors.border;

    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
        border: Border.all(
          color: borderColor,
          width: isActive || hasError ? 1.5 : AppDimensions.hairline,
        ),
      ),
      child: Text(
        digit,
        style: AppTypography.title.copyWith(color: AppColors.charcoal),
      ),
    );
  }
}

class _DevOtpHint extends StatelessWidget {
  const _DevOtpHint({required this.otp});

  final String otp;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lock_clock, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Dev OTP: $otp',
              style: AppTypography.label.copyWith(
                color: AppColors.charcoal,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
