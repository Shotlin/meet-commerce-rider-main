import 'package:flutter/foundation.dart';

import '../data/order_parser.dart';

/// Rider profile as returned by `GET /delivery/profile`.
///
/// The live backend returns **snake_case** field names with numeric
/// fields (`rating`, `commission_rate`, `current_lat`, `current_lng`)
/// delivered as **strings** (e.g. `"0.00"`, `"22.57260000"`). The
/// parser accepts both casings and converts numeric strings to the
/// appropriate Dart types via [OrderParser].
@immutable
class RiderProfile {
  /// Constructs a rider profile explicitly.
  const RiderProfile({
    required this.id,
    required this.userId,
    this.vehicleType,
    this.vehicleNumber,
    required this.isApproved,
    required this.isOnline,
    this.currentLat,
    this.currentLng,
    required this.rating,
    required this.totalDeliveries,
    required this.commissionRate,
    this.bankAccountNumber,
    this.bankIfsc,
    this.bankName,
    this.name,
    this.phone,
    this.avatarUrl,
    this.commissionEnabled = true,
    this.businessUpiId,
  });

  /// Parses the live `/delivery/profile` snake_case response.
  ///
  /// Accepts both `is_approved`/`isApproved`, `is_online`/`isOnline`,
  /// `current_lat`/`currentLat`, `current_lng`/`currentLng`, etc.
  /// Numeric fields tolerate string-encoded values.
  factory RiderProfile.fromJson(Map<String, dynamic> j) {
    return RiderProfile(
      id: OrderParser.readString(j, 'id'),
      userId: OrderParser.readString(j, 'userId', 'user_id'),
      vehicleType: OrderParser.readStringOpt(j, 'vehicleType', 'vehicle_type'),
      vehicleNumber: OrderParser.readStringOpt(
        j,
        'vehicleNumber',
        'vehicle_number',
      ),
      isApproved: OrderParser.readBool(j, 'isApproved', 'is_approved'),
      isOnline: OrderParser.readBool(j, 'isOnline', 'is_online'),
      currentLat: OrderParser.readDoubleOpt(j, 'currentLat', 'current_lat'),
      currentLng: OrderParser.readDoubleOpt(j, 'currentLng', 'current_lng'),
      rating: OrderParser.readDouble(j, 'rating'),
      totalDeliveries: OrderParser.readInt(
        j,
        'totalDeliveries',
        'total_deliveries',
      ),
      commissionRate: OrderParser.readDouble(
        j,
        'commissionRate',
        'commission_rate',
      ),
      bankAccountNumber: OrderParser.readStringOpt(
        j,
        'bankAccountNumber',
        'bank_account_number',
      ),
      bankIfsc: OrderParser.readStringOpt(j, 'bankIfsc', 'bank_ifsc'),
      bankName: OrderParser.readStringOpt(j, 'bankName', 'bank_name'),
      name: OrderParser.readStringOpt(j, 'name'),
      phone: OrderParser.readStringOpt(j, 'phone'),
      avatarUrl: OrderParser.readStringOpt(j, 'avatarUrl', 'avatar_url'),
      commissionEnabled: OrderParser.readBool(
        j,
        'commissionEnabled',
        'commission_enabled',
        true,
      ),
      businessUpiId: OrderParser.readStringOpt(
        j,
        'businessUpiId',
        'business_upi_id',
      ),
    );
  }

  /// Serialises to camelCase JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'userId': userId,
    if (vehicleType != null) 'vehicleType': vehicleType,
    if (vehicleNumber != null) 'vehicleNumber': vehicleNumber,
    'isApproved': isApproved,
    'isOnline': isOnline,
    if (currentLat != null) 'currentLat': currentLat,
    if (currentLng != null) 'currentLng': currentLng,
    'rating': rating,
    'totalDeliveries': totalDeliveries,
    'commissionRate': commissionRate,
    if (bankAccountNumber != null) 'bankAccountNumber': bankAccountNumber,
    if (bankIfsc != null) 'bankIfsc': bankIfsc,
    if (bankName != null) 'bankName': bankName,
    if (name != null) 'name': name,
    if (phone != null) 'phone': phone,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    'commissionEnabled': commissionEnabled,
    if (businessUpiId != null) 'businessUpiId': businessUpiId,
  };

  /// Returns a copy with the supplied fields replaced.
  RiderProfile copyWith({
    String? id,
    String? userId,
    String? vehicleType,
    String? vehicleNumber,
    bool? isApproved,
    bool? isOnline,
    double? currentLat,
    double? currentLng,
    double? rating,
    int? totalDeliveries,
    double? commissionRate,
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankName,
    String? name,
    String? phone,
    String? avatarUrl,
    bool? commissionEnabled,
    String? businessUpiId,
  }) {
    return RiderProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      isApproved: isApproved ?? this.isApproved,
      isOnline: isOnline ?? this.isOnline,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      rating: rating ?? this.rating,
      totalDeliveries: totalDeliveries ?? this.totalDeliveries,
      commissionRate: commissionRate ?? this.commissionRate,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankIfsc: bankIfsc ?? this.bankIfsc,
      bankName: bankName ?? this.bankName,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      commissionEnabled: commissionEnabled ?? this.commissionEnabled,
      businessUpiId: businessUpiId ?? this.businessUpiId,
    );
  }

  /// Rider profile UUID.
  final String id;

  /// Associated user UUID.
  final String userId;

  /// Vehicle type (e.g. `BIKE`, `SCOOTER`). Null until set.
  final String? vehicleType;

  /// Vehicle registration number. Null until set.
  final String? vehicleNumber;

  /// Whether the rider has been approved by the platform.
  ///
  /// This is the authoritative flag for the Approval_Gate — use this,
  /// not `RiderUser.isVerified`. The toggle-online route returns HTTP
  /// 500 with `INTERNAL_ERROR` when called against an unapproved
  /// profile (a known backend bug); checking [isApproved] before the
  /// call avoids the error path entirely.
  final bool isApproved;

  /// Whether the rider is currently online.
  final bool isOnline;

  /// Last known latitude. Null when not yet set.
  final double? currentLat;

  /// Last known longitude. Null when not yet set.
  final double? currentLng;

  /// Rider rating (0.0–5.0). Parsed from string `"0.00"` on the live
  /// backend.
  final double rating;

  /// Total deliveries completed.
  final int totalDeliveries;

  /// Platform commission rate as a percentage. Parsed from string
  /// `"15.00"` on the live backend.
  final double commissionRate;

  /// Bank account number for payouts. Null until set.
  final String? bankAccountNumber;

  /// Bank IFSC code. Null until set.
  final String? bankIfsc;

  /// Bank name. Null until set.
  final String? bankName;

  /// Rider display name (joined from the users table).
  final String? name;

  /// Rider phone number (10-digit, no `+91` prefix).
  final String? phone;

  /// Avatar URL. Null until uploaded.
  final String? avatarUrl;

  /// Whether rider commission/earnings are currently active platform-wide.
  ///
  /// `false` while riders are salary-based (item 10) — the app hides
  /// earning figures rather than trusting them to read zero, since
  /// historical `rider_earnings` rows are left untouched when the flag
  /// flips. Defaults to `true` so an older backend response missing
  /// this field doesn't unexpectedly hide earnings.
  final bool commissionEnabled;

  /// Business UPI ID (e.g. `name@upi`) admins configure for the payment QR
  /// shown to COD customers at delivery time. Null when not configured —
  /// callers should hide the QR-collection step in that case.
  final String? businessUpiId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RiderProfile) return false;
    return other.id == id &&
        other.userId == userId &&
        other.vehicleType == vehicleType &&
        other.vehicleNumber == vehicleNumber &&
        other.isApproved == isApproved &&
        other.isOnline == isOnline &&
        other.currentLat == currentLat &&
        other.currentLng == currentLng &&
        other.rating == rating &&
        other.totalDeliveries == totalDeliveries &&
        other.commissionRate == commissionRate &&
        other.bankAccountNumber == bankAccountNumber &&
        other.bankIfsc == bankIfsc &&
        other.bankName == bankName &&
        other.name == name &&
        other.phone == phone &&
        other.avatarUrl == avatarUrl &&
        other.commissionEnabled == commissionEnabled &&
        other.businessUpiId == businessUpiId;
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    vehicleType,
    vehicleNumber,
    isApproved,
    isOnline,
    currentLat,
    currentLng,
    rating,
    totalDeliveries,
    commissionRate,
    bankAccountNumber,
    bankIfsc,
    bankName,
    name,
    phone,
    avatarUrl,
    commissionEnabled,
    businessUpiId,
  );

  @override
  String toString() =>
      'RiderProfile(id=$id, isApproved=$isApproved, isOnline=$isOnline, '
      'rating=$rating)';
}
