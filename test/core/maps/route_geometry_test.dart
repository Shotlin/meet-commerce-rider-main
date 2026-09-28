import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/maps/route_geometry.dart';

void main() {
  // West 1.03 km, then south 3.34 km.
  const List<GeoPoint> route = <GeoPoint>[
    GeoPoint(22.6000, 88.3600),
    GeoPoint(22.6000, 88.3500),
    GeoPoint(22.5700, 88.3500),
  ];

  test('length sums the segments', () {
    expect(RouteGeometry.lengthMeters(route), inInclusiveRange(4300, 4450));
  });

  test('a rider on the road is ~0 m off and remaining shrinks along it', () {
    final RouteProjection atStart = RouteGeometry.project(
      route,
      route.first,
    )!;
    expect(atStart.offRouteMeters, lessThan(1));
    expect(atStart.remainingMeters, closeTo(RouteGeometry.lengthMeters(route), 5));

    final RouteProjection midSecondLeg = RouteGeometry.project(
      route,
      const GeoPoint(22.5850, 88.3500),
    )!;
    expect(midSecondLeg.segmentIndex, 1);
    expect(midSecondLeg.offRouteMeters, lessThan(1));
    expect(midSecondLeg.remainingMeters, inInclusiveRange(1600, 1750));
  });

  test('a rider away from the road reports the perpendicular distance', () {
    // 0.002° of longitude at 22.6°N ≈ 205 m west of the second leg.
    final RouteProjection off = RouteGeometry.project(
      route,
      const GeoPoint(22.5850, 88.3480),
    )!;
    expect(off.offRouteMeters, inInclusiveRange(190, 220));
    expect(off.snapped.longitude, closeTo(88.3500, 1e-6));
  });

  test('remainingPoints starts at the snapped point and keeps later vertices',
      () {
    final RouteProjection p = RouteGeometry.project(
      route,
      const GeoPoint(22.5850, 88.3500),
    )!;
    final List<GeoPoint> ahead = RouteGeometry.remainingPoints(route, p);
    expect(ahead, hasLength(2));
    expect(ahead.first, p.snapped);
    expect(ahead.last, route.last);
  });

  test('projection past the end clamps to the destination', () {
    final RouteProjection p = RouteGeometry.project(
      route,
      const GeoPoint(22.5600, 88.3500),
    )!;
    expect(p.remainingMeters, lessThan(1));
  });

  test('fewer than two points cannot be projected onto', () {
    expect(RouteGeometry.project(const <GeoPoint>[], route.first), isNull);
    expect(
      RouteGeometry.project(const <GeoPoint>[GeoPoint(1, 1)], route.first),
      isNull,
    );
  });
}
