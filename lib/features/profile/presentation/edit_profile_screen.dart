import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';
import '../../delivery/data/delivery_api.dart';
import '../../delivery/domain/rider_profile.dart';

/// Screen for editing the rider's profile fields.
///
/// Pre-fills from the currently cached [RiderProfile] and calls
/// `PATCH /delivery/profile` on save. On success it invalidates
/// [riderProfileProvider] so the profile screen refreshes automatically.
class EditProfileScreen extends ConsumerStatefulWidget {
  /// Const constructor.
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _vehicleTypeCtrl;
  late final TextEditingController _vehicleNumberCtrl;
  late final TextEditingController _bankAccountCtrl;
  late final TextEditingController _bankIfscCtrl;
  late final TextEditingController _bankNameCtrl;

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Seed controllers from the cached profile (if loaded).
    final RiderProfile? profile = ref.read(riderProfileProvider).asData?.value;
    _nameCtrl = TextEditingController(text: profile?.name ?? '');
    _vehicleTypeCtrl = TextEditingController(text: profile?.vehicleType ?? '');
    _vehicleNumberCtrl = TextEditingController(
      text: profile?.vehicleNumber ?? '',
    );
    _bankAccountCtrl = TextEditingController(
      text: profile?.bankAccountNumber ?? '',
    );
    _bankIfscCtrl = TextEditingController(text: profile?.bankIfsc ?? '');
    _bankNameCtrl = TextEditingController(text: profile?.bankName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _vehicleTypeCtrl.dispose();
    _vehicleNumberCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankIfscCtrl.dispose();
    _bankNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final DeliveryApi api = ref.read(deliveryApiProvider);
      await api.updateProfile(
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        vehicleType: _vehicleTypeCtrl.text.trim().isEmpty
            ? null
            : _vehicleTypeCtrl.text.trim().toUpperCase(),
        vehicleNumber: _vehicleNumberCtrl.text.trim().isEmpty
            ? null
            : _vehicleNumberCtrl.text.trim().toUpperCase(),
        bankAccountNumber: _bankAccountCtrl.text.trim().isEmpty
            ? null
            : _bankAccountCtrl.text.trim(),
        bankIfsc: _bankIfscCtrl.text.trim().isEmpty
            ? null
            : _bankIfscCtrl.text.trim().toUpperCase(),
        bankName: _bankNameCtrl.text.trim().isEmpty
            ? null
            : _bankNameCtrl.text.trim(),
      );

      // Refresh cached profile so profile screen shows updated values.
      ref.invalidate(riderProfileProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated')));
      context.pop();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _saving = false;
      });
    }
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
          'Edit Profile',
          style: AppTypography.heading.copyWith(color: AppColors.charcoal),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _SectionHeader(label: 'PERSONAL'),
            const SizedBox(height: 8),
            _Field(
              controller: _nameCtrl,
              label: 'Display name',
              hint: 'Your full name',
              icon: Icons.person_outline,
              validator: (String? v) {
                if (v != null && v.trim().length > 60) {
                  return 'Name must be 60 characters or fewer';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            _SectionHeader(label: 'VEHICLE'),
            const SizedBox(height: 8),
            _Field(
              controller: _vehicleTypeCtrl,
              label: 'Vehicle type',
              hint: 'e.g. BIKE, SCOOTER, AUTO',
              icon: Icons.two_wheeler_outlined,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 8),
            _Field(
              controller: _vehicleNumberCtrl,
              label: 'Vehicle number',
              hint: 'e.g. KA01AB1234',
              icon: Icons.confirmation_number_outlined,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 24),

            _SectionHeader(label: 'BANK DETAILS'),
            const SizedBox(height: 8),
            _Field(
              controller: _bankNameCtrl,
              label: 'Bank name',
              hint: 'e.g. State Bank of India',
              icon: Icons.account_balance_outlined,
            ),
            const SizedBox(height: 8),
            _Field(
              controller: _bankAccountCtrl,
              label: 'Account number',
              hint: 'Your bank account number',
              icon: Icons.credit_card_outlined,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            _Field(
              controller: _bankIfscCtrl,
              label: 'IFSC code',
              hint: 'e.g. SBIN0001234',
              icon: Icons.code_outlined,
              textCapitalization: TextCapitalization.characters,
              validator: (String? v) {
                if (v == null || v.trim().isEmpty) return null;
                // Basic IFSC format: 4 letters + 0 + 6 alphanumerics
                final RegExp ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
                if (!ifsc.hasMatch(v.trim().toUpperCase())) {
                  return 'Enter a valid IFSC code (e.g. SBIN0001234)';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            if (_errorMessage != null) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: AppTypography.body.copyWith(color: AppColors.danger),
                ),
              ),
              const SizedBox(height: 16),
            ],

            AppButton(
              label: _saving ? 'Saving…' : 'Save changes',
              onPressed: _saving ? null : _onSave,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Local widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 0),
      child: Text(
        label,
        style: AppTypography.micro.copyWith(color: AppColors.muted),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.words,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: AppTypography.body.copyWith(color: AppColors.charcoal),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: AppColors.muted),
        labelStyle: AppTypography.body.copyWith(color: AppColors.muted),
        hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.charcoal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
    );
  }
}
