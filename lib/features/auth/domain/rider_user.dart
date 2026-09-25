import 'package:flutter/foundation.dart';

/// Authenticated rider user as returned by `/auth/verify-otp`.
///
/// The live backend returns a camelCase payload:
///
/// ```json
/// {
///   "id": "uuid",
///   "phone": "9999999999",         // 10-digit, NO +91 prefix
///   "name": "Priya Nair",
///   "role": "RIDER",
///   "isNewUser": false,
///   "isVerified": false            // tracks rider-profile approval
/// }
/// ```
///
/// `isVerified` here is the user-table flag, not the rider-profile
/// approval state. The Approval_Gate uses `is_approved` from
/// `/delivery/profile`, which is more authoritative; `RiderUser.isVerified`
/// is mostly informational.
@immutable
class RiderUser {
  /// Constructs a rider user explicitly.
  const RiderUser({
    required this.id,
    required this.phone,
    required this.role,
    required this.isNewUser,
    required this.isVerified,
    this.name,
  });

  /// Lenient parser. Accepts both casings for safety; the live backend
  /// returns camelCase here today.
  factory RiderUser.fromJson(Map<String, dynamic> json) {
    return RiderUser(
      id: json['id'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? '',
      name: json['name'] as String?,
      isNewUser: _readBool(json['isNewUser'] ?? json['is_new_user']) ?? false,
      isVerified: _readBool(json['isVerified'] ?? json['is_verified']) ?? false,
    );
  }

  /// Stable user id (UUID).
  final String id;

  /// 10-digit Indian phone number, no `+91` prefix (matches the wire
  /// format the backend uses).
  final String phone;

  /// Optional display name.
  final String? name;

  /// Backend role; for rider builds this should be `RIDER`. The Flutter
  /// auth controller treats anything else as a sign-in error.
  final String role;

  /// True when the user record was created during this verify-OTP call.
  final bool isNewUser;

  /// User-table verified flag. Note: the rider-profile approval gate
  /// reads `is_approved` from `/delivery/profile` instead; this field
  /// is informational only.
  final bool isVerified;

  /// Convenience: phone with `+91` prefix re-applied for UI display.
  String get e164Phone => phone.startsWith('+') ? phone : '+91$phone';

  /// Convenience: true when [role] equals the canonical rider role.
  bool get isRider => role.toUpperCase() == 'RIDER';

  /// Pure value-equality so tests and providers can compare instances.
  @override
  bool operator ==(Object other) {
    return other is RiderUser &&
        other.id == id &&
        other.phone == phone &&
        other.name == name &&
        other.role == role &&
        other.isNewUser == isNewUser &&
        other.isVerified == isVerified;
  }

  @override
  int get hashCode => Object.hash(id, phone, name, role, isNewUser, isVerified);

  @override
  String toString() {
    return 'RiderUser(id=$id, phone=$phone, role=$role, '
        'isNewUser=$isNewUser, isVerified=$isVerified)';
  }

  static bool? _readBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'true':
        case '1':
          return true;
        case 'false':
        case '0':
          return false;
      }
    }
    return null;
  }
}
