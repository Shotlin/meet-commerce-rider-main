import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:meet_commerce_rider_main/core/network/api_envelope.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_history_entry.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/payout.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/pickup_session.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_earnings.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_profile.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_stats.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/store_info.dart';

/// Captured record of a [FakeDeliveryApi.markDelivered] call.
@immutable
class CapturedMarkDelivered {
  /// Constructs a captured mark-delivered call.
  const CapturedMarkDelivered({
    required this.orderId,
    this.proofPhotoUrl,
    this.demoMode,
    this.cashCollected,
    this.upiCollected,
  });

  /// The order id passed to markDelivered.
  final String orderId;

  /// Proof photo URL if supplied.
  final String? proofPhotoUrl;

  /// demoMode flag if supplied.
  final bool? demoMode;

  /// Cash-collected amount if supplied.
  final double? cashCollected;

  /// UPI-collected amount if supplied.
  final double? upiCollected;
}

/// Hand-rolled fake implementation of [DeliveryApi] for integration tests.
///
/// Behaviour per method is described in the spec's FakeDeliveryApi section.
/// Call counts and argument captures are exposed so tests can assert on
/// them after each step.
class FakeDeliveryApi implements DeliveryApi {
  // ---------------------------------------------------------------------------
  // Seed data (constructed once, reused across calls)
  // ---------------------------------------------------------------------------

  static final RiderProfile _seedProfile = RiderProfile(
    id: 'profile-001',
    userId: 'user-001',
    isApproved: true,
    isOnline: true,
    rating: 4.8,
    totalDeliveries: 42,
    commissionRate: 15.0,
    name: 'Test Rider',
    phone: '9876543210',
  );

  static final StoreInfo _seedStoreInfo = StoreInfo(
    name: 'FreshCuts Store',
    address: 'Salt Lake, Kolkata',
    lat: 22.57,
    lng: 88.36,
  );

  static final RiderStats _zeroStats = RiderStats(
    totalAssigned: 0,
    totalDelivered: 0,
    deliveredToday: 0,
    deliveriesToday: 0,
    totalEarnings: 0,
    earningsToday: 0,
    earningsThisWeek: 0,
    weeklyData: const <DailyStats>[],
    rating: 0,
    totalDeliveries: 0,
    acceptanceRate: 0,
    dailyTarget: 0,
  );

  static final RiderEarnings _zeroEarnings = RiderEarnings(
    period: 'today',
    totalEarnings: 0,
    deliveriesCount: 0,
    avgPerDelivery: 0,
    breakdown: const EarningsBreakdown(
      baseDeliveryFees: 0,
      distanceBonus: 0,
      performanceBonus: 0,
      tips: 0,
    ),
    dailyBreakdown: const <DailyEarning>[],
    pendingPayout: 0,
    alreadyPaid: 0,
    lastPayoutAmount: 0,
    rating: 0,
  );

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Populated by [assignOrder] / [assignOrders] so [getOrders] can
  /// return the seeded order(s) — simulating one or more backend
  /// "assignment" events.
  List<DeliveryOrder> _assignedOrders = const <DeliveryOrder>[];

  // ---------------------------------------------------------------------------
  // Call-count / argument captures
  // ---------------------------------------------------------------------------

  /// Number of times [getProfile] was called.
  int getProfileCallCount = 0;

  /// List of [isOnline] values passed to [toggleOnline].
  final List<bool> toggleOnlineCalls = <bool>[];

  /// List of (lat, lng) pairs passed to [updateLocation].
  final List<(double lat, double lng)> updateLocationCalls =
      <(double lat, double lng)>[];

  /// Number of times [getOrders] was called.
  int getOrdersCallCount = 0;

  /// List of order ids passed to [acceptOrder].
  final List<String> acceptOrderCalls = <String>[];

  /// List of order ids passed to [markPickedUp].
  final List<String> markPickedUpCalls = <String>[];

  /// List of captured [markDelivered] calls.
  final List<CapturedMarkDelivered> markDeliveredCalls =
      <CapturedMarkDelivered>[];

  /// Number of times [getStats] was called.
  int getStatsCallCount = 0;

  /// Number of times [getEarnings] was called.
  int getEarningsCallCount = 0;

  // ---------------------------------------------------------------------------
  // Test helper
  // ---------------------------------------------------------------------------

  /// Seeds the fake with [order] so that [getOrders] will return it on
  /// the next call (simulating a backend "assignment" event).
  void assignOrder(DeliveryOrder order) {
    _assignedOrders = <DeliveryOrder>[order];
  }

  /// Seeds the fake with multiple [orders] so [getOrders] returns all of
  /// them — simulating a rider with more than one active assignment
  /// (item 8/9 multi-stop tests).
  void assignOrders(List<DeliveryOrder> orders) {
    _assignedOrders = orders;
  }

  // ---------------------------------------------------------------------------
  // DeliveryApi implementation
  // ---------------------------------------------------------------------------

  @override
  Future<RiderProfile> getProfile() async {
    getProfileCallCount++;
    return _seedProfile;
  }

  @override
  Future<void> toggleOnline(bool isOnline) async {
    toggleOnlineCalls.add(isOnline);
  }

  @override
  Future<void> updateLocation(double latitude, double longitude) async {
    updateLocationCalls.add((latitude, longitude));
  }

  @override
  Future<List<DeliveryOrder>> getOrders({String? status}) async {
    getOrdersCallCount++;
    return _assignedOrders;
  }

  @override
  Future<Map<String, dynamic>> acceptOrder(String orderId) async {
    acceptOrderCalls.add(orderId);
    // Return the matching seeded order updated with ACCEPTED status,
    // falling back to the first seeded order for callers that don't
    // care which specific order comes back.
    DeliveryOrder? base;
    for (final DeliveryOrder order in _assignedOrders) {
      if (order.orderId == orderId) {
        base = order;
        break;
      }
    }
    base ??= _assignedOrders.isNotEmpty ? _assignedOrders.first : null;
    if (base == null) {
      return <String, dynamic>{
        'orderId': orderId,
        'assignmentStatus': 'ACCEPTED',
      };
    }
    final DeliveryOrder accepted = base.copyWith(
      assignmentStatus: AssignmentStatus.accepted,
    );
    return accepted.toJson();
  }

  @override
  Future<void> markPickedUp(String orderId) async {
    markPickedUpCalls.add(orderId);
  }

  @override
  Future<PickupVerification> verifyScan(Map<String, dynamic> payload) {
    throw UnsupportedError('FakeDeliveryApi.verifyScan not implemented');
  }

  @override
  Future<PickupVerification> getPendingChecklist(String orderId) {
    throw UnsupportedError(
      'FakeDeliveryApi.getPendingChecklist not implemented',
    );
  }

  @override
  Future<void> markDelivered(
    String orderId, {
    String? proofPhotoUrl,
    bool? demoMode,
    double? cashCollected,
    double? upiCollected,
  }) async {
    assert(
      demoMode == true,
      'FakeDeliveryApi.markDelivered: expected demoMode==true '
      'but got demoMode=$demoMode',
    );
    markDeliveredCalls.add(
      CapturedMarkDelivered(
        orderId: orderId,
        proofPhotoUrl: proofPhotoUrl,
        demoMode: demoMode,
        cashCollected: cashCollected,
        upiCollected: upiCollected,
      ),
    );
  }

  @override
  Future<StoreInfo> getStoreInfo() async {
    return _seedStoreInfo;
  }

  @override
  Future<RiderStats> getStats() async {
    getStatsCallCount++;
    return _zeroStats;
  }

  @override
  Future<RiderEarnings> getEarnings(EarningsPeriod period) async {
    getEarningsCallCount++;
    return _zeroEarnings.copyWith(period: period.wire);
  }

  // ---------------------------------------------------------------------------
  // Unsupported methods (not needed for this integration test path)
  // ---------------------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> getDocuments() {
    throw UnsupportedError('FakeDeliveryApi.getDocuments not implemented');
  }

  @override
  Future<void> rejectOrder(String orderId, String reason) {
    throw UnsupportedError('FakeDeliveryApi.rejectOrder not implemented');
  }

  @override
  Future<void> cancelDelivery(String orderId, String reason) {
    throw UnsupportedError('FakeDeliveryApi.cancelDelivery not implemented');
  }

  @override
  Future<RiderProfile> updateProfile({
    String? name,
    String? vehicleType,
    String? vehicleNumber,
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankName,
  }) {
    throw UnsupportedError('FakeDeliveryApi.updateProfile not implemented');
  }

  @override
  Future<String> uploadProof(String orderId, File file) {
    throw UnsupportedError('FakeDeliveryApi.uploadProof not implemented');
  }

  @override
  Future<({List<Payout> items, Pagination pagination})> getPayouts({
    int page = 1,
    int limit = 20,
  }) {
    throw UnsupportedError('FakeDeliveryApi.getPayouts not implemented');
  }

  @override
  Future<({List<DeliveryHistoryEntry> orders, int total})> getHistory({
    int page = 1,
    int limit = 20,
  }) {
    throw UnsupportedError('FakeDeliveryApi.getHistory not implemented');
  }
}
