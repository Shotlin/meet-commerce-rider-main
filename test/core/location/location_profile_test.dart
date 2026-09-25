import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/config/app_constants.dart';
import 'package:meet_commerce_rider_main/core/location/location_profile.dart';

void main() {
  group('LocationProfileConfig.forProfile', () {
    test('offline disables streaming and sets budget to zero', () {
      final LocationProfileConfig c = LocationProfileConfig.forProfile(
        LocationProfile.offline,
      );
      expect(c.accuracy, LocationAccuracyTier.off);
      expect(c.distanceFilterMeters, 0);
      expect(c.rateBudgetPerMinute, 0);
      expect(c.minInterval, Duration.zero);
    });

    test('waitingOnline matches AppConstants', () {
      final LocationProfileConfig c = LocationProfileConfig.forProfile(
        LocationProfile.waitingOnline,
      );
      expect(c.accuracy, LocationAccuracyTier.medium);
      expect(
        c.distanceFilterMeters,
        AppConstants.locationDistanceFilterWaitingMeters,
      );
      expect(
        c.rateBudgetPerMinute,
        AppConstants.locationBudgetWaitingPerMinute,
      );
      expect(c.minInterval, const Duration(seconds: 30));
    });

    test('acceptedToStore matches AppConstants', () {
      final LocationProfileConfig c = LocationProfileConfig.forProfile(
        LocationProfile.acceptedToStore,
      );
      expect(c.accuracy, LocationAccuracyTier.high);
      expect(
        c.distanceFilterMeters,
        AppConstants.locationDistanceFilterAcceptedMeters,
      );
      expect(
        c.rateBudgetPerMinute,
        AppConstants.locationBudgetAcceptedPerMinute,
      );
      expect(c.minInterval, const Duration(seconds: 10));
    });

    test('inTransitToCustomer matches AppConstants', () {
      final LocationProfileConfig c = LocationProfileConfig.forProfile(
        LocationProfile.inTransitToCustomer,
      );
      expect(c.accuracy, LocationAccuracyTier.high);
      expect(
        c.distanceFilterMeters,
        AppConstants.locationDistanceFilterInTransitMeters,
      );
      expect(
        c.rateBudgetPerMinute,
        AppConstants.locationBudgetInTransitPerMinute,
      );
      expect(c.minInterval, const Duration(seconds: 5));
    });
  });
}
