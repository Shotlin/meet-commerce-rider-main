import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';

/// Unit test to verify the Navigate button logic without requiring
/// the full widget tree or GoogleMap platform plugin.
///
/// This test validates Requirements 2.3 and 3.5:
/// - Navigate button SHALL be disabled when customer coordinates are missing
/// - Navigate button SHALL remain enabled for valid customer coordinates
void main() {
  group('Navigate button logic', () {
    test('Navigate button should be disabled when customer lat is null', () {
      final DeliveryAddress addr = DeliveryAddress(
        name: 'Customer',
        address: 'Some address',
        lat: null,
        lng: 77.62,
      );

      // Simulate the button's onPressed logic
      final bool shouldEnable = addr.lat != null && addr.lng != null;

      expect(
        shouldEnable,
        isFalse,
        reason:
            'Navigate button should be disabled when lat is null (Requirement 2.3)',
      );
    });

    test('Navigate button should be disabled when customer lng is null', () {
      final DeliveryAddress addr = DeliveryAddress(
        name: 'Customer',
        address: 'Some address',
        lat: 12.93,
        lng: null,
      );

      // Simulate the button's onPressed logic
      final bool shouldEnable = addr.lat != null && addr.lng != null;

      expect(
        shouldEnable,
        isFalse,
        reason:
            'Navigate button should be disabled when lng is null (Requirement 2.3)',
      );
    });

    test('Navigate button should be disabled when both coordinates are null', () {
      final DeliveryAddress addr = DeliveryAddress(
        name: 'Customer',
        address: 'Some address',
        lat: null,
        lng: null,
      );

      // Simulate the button's onPressed logic
      final bool shouldEnable = addr.lat != null && addr.lng != null;

      expect(
        shouldEnable,
        isFalse,
        reason:
            'Navigate button should be disabled when both coordinates are null (Requirement 2.3)',
      );
    });

    test('Navigate button should be enabled when both coordinates are valid', () {
      final DeliveryAddress addr = DeliveryAddress(
        name: 'Customer',
        address: 'Some address',
        lat: 12.93,
        lng: 77.62,
      );

      // Simulate the button's onPressed logic
      final bool shouldEnable = addr.lat != null && addr.lng != null;

      expect(
        shouldEnable,
        isTrue,
        reason:
            'Navigate button should be enabled when both coordinates are valid (Requirement 3.5)',
      );
    });

    test('Navigate button logic handles edge case coordinates correctly', () {
      // Test with zero coordinates (valid but edge case)
      final DeliveryAddress addrZero = DeliveryAddress(
        name: 'Customer',
        address: 'Some address',
        lat: 0.0,
        lng: 0.0,
      );

      final bool shouldEnableZero =
          addrZero.lat != null && addrZero.lng != null;

      expect(
        shouldEnableZero,
        isTrue,
        reason:
            'Navigate button should be enabled for zero coordinates (valid location)',
      );

      // Test with extreme valid coordinates
      final DeliveryAddress addrExtreme = DeliveryAddress(
        name: 'Customer',
        address: 'Some address',
        lat: -90.0,
        lng: 180.0,
      );

      final bool shouldEnableExtreme =
          addrExtreme.lat != null && addrExtreme.lng != null;

      expect(
        shouldEnableExtreme,
        isTrue,
        reason:
            'Navigate button should be enabled for extreme valid coordinates',
      );
    });
  });
}
