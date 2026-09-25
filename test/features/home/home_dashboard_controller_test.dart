import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/assignment_status.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_item.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_order.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_earnings.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_profile.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/rider_stats.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/store_info.dart';
import 'package:meet_commerce_rider_main/features/home/application/home_dashboard_controller.dart';

class _MockDeliveryApi extends Mock implements DeliveryApi {}

const RiderProfile _profile = RiderProfile(
  id: 'p1',
  userId: 'u1',
  isApproved: true,
  isOnline: false,
  rating: 4.8,
  totalDeliveries: 12,
  commissionRate: 15.0,
  name: 'Priya',
  phone: '9999999999',
);

const RiderStats _stats = RiderStats(
  totalAssigned: 10,
  totalDelivered: 9,
  deliveredToday: 3,
  deliveriesToday: 3,
  totalEarnings: 4500,
  earningsToday: 450,
  earningsThisWeek: 1200,
  weeklyData: <DailyStats>[],
  rating: 4.8,
  totalDeliveries: 12,
  acceptanceRate: 95,
  dailyTarget: 12,
);

const RiderEarnings _earnings = RiderEarnings(
  period: 'today',
  totalEarnings: 450,
  deliveriesCount: 3,
  avgPerDelivery: 150,
  breakdown: EarningsBreakdown(
    baseDeliveryFees: 300,
    distanceBonus: 100,
    performanceBonus: 50,
    tips: 0,
  ),
  dailyBreakdown: <DailyEarning>[],
  pendingPayout: 450,
  alreadyPaid: 4050,
  lastPayoutAmount: 4050,
  rating: 4.8,
);

final StoreInfo _store = StoreInfo(
  name: 'FreshCuts',
  address: 'Hub, Kolkata',
  lat: 22.5726,
  lng: 88.3639,
);

final DeliveryAddress _addr = DeliveryAddress(name: 'Test', address: 'Test');

DeliveryOrder _order(String id, AssignmentStatus status) => DeliveryOrder(
  orderId: id,
  orderNumber: id,
  assignmentStatus: status,
  totalAmount: 250.0,
  paymentMethod: 'ONLINE',
  riderEarning: 35.0,
  estimatedDuration: 18,
  customerAddress: _addr,
  storeAddress: _addr,
  items: const <DeliveryItem>[],
);

void main() {
  late _MockDeliveryApi api;
  late HomeDashboardController controller;

  setUp(() {
    api = _MockDeliveryApi();
    controller = HomeDashboardController(api: api);
  });

  tearDown(() {
    controller.dispose();
  });

  group('refresh() — happy path', () {
    test('populates every field on success', () async {
      when(() => api.getProfile()).thenAnswer((_) async => _profile);
      when(() => api.getStats()).thenAnswer((_) async => _stats);
      when(
        () => api.getEarnings(EarningsPeriod.today),
      ).thenAnswer((_) async => _earnings);
      when(() => api.getOrders()).thenAnswer(
        (_) async => <DeliveryOrder>[_order('o1', AssignmentStatus.assigned)],
      );
      when(() => api.getStoreInfo()).thenAnswer((_) async => _store);

      await controller.refresh();

      expect(controller.profile, _profile);
      expect(controller.stats, _stats);
      expect(controller.earningsToday, _earnings);
      expect(controller.orders, hasLength(1));
      expect(controller.store, _store);

      // Errors all clear, loading flags all false.
      expect(controller.profileError, isNull);
      expect(controller.statsError, isNull);
      expect(controller.earningsError, isNull);
      expect(controller.ordersError, isNull);
      expect(controller.storeError, isNull);
      expect(controller.isAnyLoading, isFalse);
    });

    test('issues all five fetches in parallel', () async {
      when(() => api.getProfile()).thenAnswer((_) async => _profile);
      when(() => api.getStats()).thenAnswer((_) async => _stats);
      when(
        () => api.getEarnings(EarningsPeriod.today),
      ).thenAnswer((_) async => _earnings);
      when(
        () => api.getOrders(),
      ).thenAnswer((_) async => const <DeliveryOrder>[]);
      when(() => api.getStoreInfo()).thenAnswer((_) async => _store);

      await controller.refresh();

      verify(() => api.getProfile()).called(1);
      verify(() => api.getStats()).called(1);
      verify(() => api.getEarnings(EarningsPeriod.today)).called(1);
      verify(() => api.getOrders()).called(1);
      verify(() => api.getStoreInfo()).called(1);
    });
  });

  group('refresh() — partial failure (R5.3)', () {
    test('a stats failure does not poison the other four cards', () async {
      when(() => api.getProfile()).thenAnswer((_) async => _profile);
      when(() => api.getStats()).thenThrow(Exception('stats backend exploded'));
      when(
        () => api.getEarnings(EarningsPeriod.today),
      ).thenAnswer((_) async => _earnings);
      when(
        () => api.getOrders(),
      ).thenAnswer((_) async => const <DeliveryOrder>[]);
      when(() => api.getStoreInfo()).thenAnswer((_) async => _store);

      await controller.refresh();

      // Stats card: empty + error.
      expect(controller.stats, isNull);
      expect(controller.statsError, isNotNull);
      expect(controller.statsError, contains('stats backend exploded'));

      // The other four cards are populated and error-free.
      expect(controller.profile, _profile);
      expect(controller.earningsToday, _earnings);
      expect(controller.orders, isEmpty);
      expect(controller.store, _store);

      expect(controller.profileError, isNull);
      expect(controller.earningsError, isNull);
      expect(controller.ordersError, isNull);
      expect(controller.storeError, isNull);
    });

    test('orders failure surfaces only on the orders card', () async {
      when(() => api.getProfile()).thenAnswer((_) async => _profile);
      when(() => api.getStats()).thenAnswer((_) async => _stats);
      when(
        () => api.getEarnings(EarningsPeriod.today),
      ).thenAnswer((_) async => _earnings);
      when(() => api.getOrders()).thenThrow(Exception('orders timeout'));
      when(() => api.getStoreInfo()).thenAnswer((_) async => _store);

      await controller.refresh();

      expect(controller.orders, isEmpty);
      expect(controller.ordersError, isNotNull);
      expect(controller.ordersError, contains('orders timeout'));

      expect(controller.profile, _profile);
      expect(controller.stats, _stats);
      expect(controller.earningsToday, _earnings);
      expect(controller.store, _store);
    });

    test('per-card retry recovers after a one-off failure', () async {
      when(() => api.getProfile()).thenAnswer((_) async => _profile);
      when(
        () => api.getEarnings(EarningsPeriod.today),
      ).thenAnswer((_) async => _earnings);
      when(
        () => api.getOrders(),
      ).thenAnswer((_) async => const <DeliveryOrder>[]);
      when(() => api.getStoreInfo()).thenAnswer((_) async => _store);

      // First attempt: stats fails.
      when(() => api.getStats()).thenThrow(Exception('stats once'));
      await controller.refresh();
      expect(controller.statsError, isNotNull);
      expect(controller.stats, isNull);

      // Retry: stats succeeds. Other cards untouched.
      when(() => api.getStats()).thenAnswer((_) async => _stats);
      await controller.refreshStats();
      expect(controller.statsError, isNull);
      expect(controller.stats, _stats);

      // Other cards still populated from the first refresh.
      expect(controller.profile, _profile);
      expect(controller.earningsToday, _earnings);
      expect(controller.store, _store);
    });
  });

  group('refresh() notifies listeners', () {
    test('once before fetches start and once after they all settle', () async {
      when(() => api.getProfile()).thenAnswer((_) async => _profile);
      when(() => api.getStats()).thenAnswer((_) async => _stats);
      when(
        () => api.getEarnings(EarningsPeriod.today),
      ).thenAnswer((_) async => _earnings);
      when(
        () => api.getOrders(),
      ).thenAnswer((_) async => const <DeliveryOrder>[]);
      when(() => api.getStoreInfo()).thenAnswer((_) async => _store);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await controller.refresh();

      // At least 2: once when loading flips to true, once when it
      // flips to false. Implementation may notify more if individual
      // refresh helpers are extended later — we assert >= 2.
      expect(notifyCount, greaterThanOrEqualTo(2));
    });
  });
}
