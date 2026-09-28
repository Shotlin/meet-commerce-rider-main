import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/maps/marker_icon_renderer.dart';
import 'package:meet_commerce_rider_main/core/maps/rider_map.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/delivery_address.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rider, store and customer each get a distinct icon style', () {
    final Set<int> icons = <int>{};
    for (final RiderMarkerKind k in <RiderMarkerKind>[
      RiderMarkerKind.rider,
      RiderMarkerKind.store,
      RiderMarkerKind.customer,
    ]) {
      final RiderMarkerStyle? style = RiderMarkerStyle.of(k);
      expect(style, isNotNull, reason: '$k needs an icon');
      icons.add(style!.icon.codePoint);
    }
    expect(icons, hasLength(3));
    expect(RiderMarkerStyle.of(RiderMarkerKind.dot), isNull);
  });

  test('image names are unique per kind', () {
    final Set<String> names = RiderMarkerKind.values
        .map(riderMarkerImageName)
        .toSet();
    expect(names, hasLength(RiderMarkerKind.values.length));
  });

  test('riderMarkersForOrder tags rider / store / customer kinds', () {
    final DeliveryAddress store = DeliveryAddress(
      name: 'Store',
      address: '1 Park St',
      lat: 22.5,
      lng: 88.3,
    );
    final DeliveryAddress customer = DeliveryAddress(
      name: 'Customer',
      address: '2 Lake Rd',
      lat: 22.6,
      lng: 88.4,
    );
    final Map<String, RiderMarkerKind> kinds = <String, RiderMarkerKind>{
      for (final RiderMarkerSpec m in riderMarkersForOrder(
        store: store,
        customer: customer,
        rider: const GeoPoint(22.55, 88.35),
      ))
        m.id: m.kind,
    };
    expect(kinds, <String, RiderMarkerKind>{
      'rider': RiderMarkerKind.rider,
      'store': RiderMarkerKind.store,
      'customer': RiderMarkerKind.customer,
    });
  });

  testWidgets('renderRiderMarkerIcon produces a PNG', (WidgetTester tester) async {
    final Uint8List? bytes = await tester.runAsync(
      () => renderRiderMarkerIcon(RiderMarkerStyle.of(RiderMarkerKind.rider)!),
    );
    expect(bytes, isNotNull);
    // PNG signature.
    expect(bytes!.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
    expect(bytes.length, greaterThan(500));
  });
}
