import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';

/// Single text input widget for the Meet Commerce Rider App.
///
/// Wraps a Material [TextField] with the rider app's visual contract:
/// label above the input in [AppTypography.label], optional error below
/// in [AppTypography.micro] colored [AppColors.danger], 14-radius border
/// outline, [AppColors.offWhite] background, and a 14x16 content padding.
/// Border switches to [AppColors.charcoal] on focus and [AppColors.danger]
/// when [errorText] is non-null.
///
/// Used by the phone login, OTP, and any screen that collects free-form
/// text (e.g., reject-reason "OTHER", proof captions if added later).
class AppTextField extends StatefulWidget {
  /// Creates a text field bound to [controller] and styled per the
  /// rider app's text-input language.
  const AppTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.keyboardType,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.autofocus = false,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.enabled = true,
    this.maxLength,
  });

  /// Owns the field's text. Callers create the controller and dispose it.
  final TextEditingController controller;

  /// Optional label rendered above the input in [AppTypography.label].
  final String? label;

  /// Optional placeholder text rendered when the field is empty.
  final String? hint;

  /// Optional inline error rendered below the input. When non-null the
  /// border switches to [AppColors.danger].
  final String? errorText;

  /// Optional keyboard type passed straight through to [TextField].
  final TextInputType? keyboardType;

  /// Optional input formatters (digit-only filters, length cappers, etc.).
  final List<TextInputFormatter>? inputFormatters;

  /// Optional widget rendered inside the input on the leading edge.
  final Widget? prefixIcon;

  /// Optional widget rendered inside the input on the trailing edge.
  final Widget? suffixIcon;

  /// Whether the field requests focus when mounted.
  final bool autofocus;

  /// Optional [TextInputAction] for the soft keyboard's action key.
  final TextInputAction? textInputAction;

  /// Optional change callback, fired on every keystroke.
  final ValueChanged<String>? onChanged;

  /// Optional submit callback, fired when the soft keyboard's action key
  /// is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Whether to obscure entered text (used for OTP-like inputs).
  final bool obscureText;

  /// Whether the input accepts input. Disabled fields render with the
  /// muted foreground color.
  final bool enabled;

  /// Optional max character length passed through to [TextField].
  final int? maxLength;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Color _resolveBorderColor() {
    if (widget.errorText != null) {
      return AppColors.danger;
    }
    if (_focusNode.hasFocus) {
      return AppColors.charcoal;
    }
    return AppColors.border;
  }

  @override
  Widget build(BuildContext context) {
    final Color borderColor = _resolveBorderColor();
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
      borderSide: BorderSide(color: borderColor, width: 1),
    );

    final Widget field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      obscureText: widget.obscureText,
      enabled: widget.enabled,
      maxLength: widget.maxLength,
      style: AppTypography.body,
      cursorColor: AppColors.charcoal,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.suffixIcon,
        filled: true,
        fillColor: AppColors.offWhite,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        counterText: '',
        border: border,
        enabledBorder: border,
        focusedBorder: border,
        disabledBorder: border,
        errorBorder: border,
        focusedErrorBorder: border,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.label != null) ...<Widget>[
          Text(
            widget.label!,
            style: AppTypography.label.copyWith(color: AppColors.charcoal),
          ),
          const SizedBox(height: 6),
        ],
        field,
        if (widget.errorText != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: AppTypography.micro.copyWith(color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}
