import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/core/maps/geo_point.dart';
import 'package:meet_commerce_rider_main/core/maps/rider_maps_service.dart';
import 'package:meet_commerce_rider_main/core/network/api_client.dart';
import 'package:meet_commerce_rider_main/core/network/api_envelope.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

ApiEnvelope<Map<String, dynamic>> _envelope(Map<String, dynamic> data) {
  return ApiEnvelope<Map<String, dynamic>>(
    success: true,
    message: 'ok',
    data: data,
  );
}

void main() {
  late _MockApiClient client;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    client = _MockApiClient();
    when(() => client.baseUrl).thenReturn('https://api.fc.opslin.com/api/v1');
  });

  group('RiderMapsService.getStyle', () {
    test('returns the backend style URL when configured', () async {
      when(
        () => client.get<Map<String, dynamic>>(
          '/maps/ola/style-url',
          parseData: any(named: 'parseData'),
        ),
      ).thenAnswer(
        (_) async => _envelope(<String, dynamic>{
          'configured': true,
          'styleUrl': 'https://api.fc.opslin.com/api/v1/maps/ola/style.json',
        }),
      );

      final OlaMapsAvailability availability = await RiderMapsService(
        client,
      ).getStyle();

      expect(availability.configured, isTrue);
      expect(
        availability.styleUrl,
        'https://api.fc.opslin.com/api/v1/maps/ola/style.json',
      );
    });

    test('upgrades an http style URL on the https API host to https '
        '(clear-text proxy lesson)', () async {
      when(
        () => client.get<Map<String, dynamic>>(
          '/maps/ola/style-url',
          parseData: any(named: 'parseData'),
        ),
      ).thenAnswer(
        (_) async => _envelope(<String, dynamic>{
          'configured': true,
          'styleUrl': 'http://api.fc.opslin.com/api/v1/maps/ola/style.json',
        }),
      );

      final OlaMapsAvailability availability = await RiderMapsService(
        client,
      ).getStyle();

      expect(
        availability.styleUrl,
        'https://api.fc.opslin.com/api/v1/maps/ola/style.json',
      );
    });

    test('a backend failure reads as unconfigured, never throws', () async {
      when(
        () => client.get<Map<String, dynamic>>(
          '/maps/ola/style-url',
          parseData: any(named: 'parseData'),
        ),
      ).thenThrow(Exception('boom'));

      final OlaMapsAvailability availability = await RiderMapsService(
        client,
      ).getStyle();

      expect(availability.configured, isFalse);
      expect(availability.styleUrl, isNull);
      expect(availability, OlaMapsAvailability.unconfigured);
    });

    test('configured=false data reads as unconfigured', () async {
      when(
        () => client.get<Map<String, dynamic>>(
          '/maps/ola/style-url',
          parseData: any(named: 'parseData'),
        ),
      ).thenAnswer(
        (_) async =>
            _envelope(<String, dynamic>{'configured': false, 'styleUrl': null}),
      );

      expect((await RiderMapsService(client).getStyle()).configured, isFalse);
    });
  });

  group('RiderMapsService.getRoute', () {
    test('parses the proxied Ola directions shape', () async {
      when(
        () => client.get<Map<String, dynamic>>(
          '/maps/ola/directions',
          queryParameters: any(named: 'queryParameters'),
          parseData: any(named: 'parseData'),
        ),
      ).thenAnswer(
        (_) async => _envelope(<String, dynamic>{
          'configured': true,
          'result': <String, dynamic>{
            'points': <dynamic>[
              <String, dynamic>{'lat': 12.97, 'lng': 77.59},
              <String, dynamic>{'lat': 12.96, 'lng': 77.60},
              <String, dynamic>{'lat': 12.95, 'lng': 77.61},
            ],
            'distanceMeters': 3400,
            'durationSeconds': 600,
          },
        }),
      );

      final RiderRoute route = await RiderMapsService(
        client,
      ).getRoute(const GeoPoint(12.97, 77.59), const GeoPoint(12.95, 77.61));

      expect(route.points, hasLength(3));
      expect(route.distanceMeters, 3400);
      expect(route.durationSeconds, 600);
    });

    test(
      'falls back to a straight line when the proxy yields nothing',
      () async {
        when(
          () => client.get<Map<String, dynamic>>(
            '/maps/ola/directions',
            queryParameters: any(named: 'queryParameters'),
            parseData: any(named: 'parseData'),
          ),
        ).thenAnswer(
          (_) async => _envelope(<String, dynamic>{
            'configured': true,
            'result': <String, dynamic>{'points': <dynamic>[]},
          }),
        );

        final RiderRoute route = await RiderMapsService(
          client,
        ).getRoute(const GeoPoint(12.97, 77.59), const GeoPoint(12.95, 77.61));

        expect(route.points, hasLength(2));
        expect(route.points.first.latitude, 12.97);
        expect(route.points.last.longitude, 77.61);
        expect(route.distanceMeters, greaterThan(0));
        expect(route.durationSeconds, greaterThan(0));
      },
    );

    test('falls back to a straight line when the proxy throws', () async {
      when(
        () => client.get<Map<String, dynamic>>(
          '/maps/ola/directions',
          queryParameters: any(named: 'queryParameters'),
          parseData: any(named: 'parseData'),
        ),
      ).thenThrow(Exception('offline'));

      final RiderRoute route = await RiderMapsService(
        client,
      ).getRoute(const GeoPoint(12.97, 77.59), const GeoPoint(12.95, 77.61));

      expect(route.points, hasLength(2));
    });
  });

  group('RiderMapsService.getAreaLabel', () {
    test('prefers sublocality, then city, from the reverse-geocode '
        'components', () async {
      when(
        () => client.get<Map<String, dynamic>>(
          '/maps/ola/reverse-geocode',
          queryParameters: any(named: 'queryParameters'),
          parseData: any(named: 'parseData'),
        ),
      ).thenAnswer(
        (_) async => _envelope(<String, dynamic>{
          'configured': true,
          'result': <String, dynamic>{
            'results': <dynamic>[
              <String, dynamic>{
                'formatted_address': '12 MG Road, Salt Lake, Kolkata 700091',
                'address_components': <dynamic>[
                  <String, dynamic>{
                    'long_name': 'Salt Lake',
                    'types': <dynamic>['sublocality'],
                  },
                  <String, dynamic>{
                    'long_name': 'Kolkata',
                    'types': <dynamic>['locality'],
                  },
                ],
              },
            ],
          },
        }),
      );

      final String? label = await RiderMapsService(
        client,
      ).getAreaLabel(const GeoPoint(22.57, 88.36));

      expect(label, 'Salt Lake');
    });

    test('returns null when the proxy yields no results', () async {
      when(
        () => client.get<Map<String, dynamic>>(
          '/maps/ola/reverse-geocode',
          queryParameters: any(named: 'queryParameters'),
          parseData: any(named: 'parseData'),
        ),
      ).thenAnswer(
        (_) async => _envelope(<String, dynamic>{
          'configured': true,
          'result': <String, dynamic>{'results': <dynamic>[]},
        }),
      );

      expect(
        await RiderMapsService(
          client,
        ).getAreaLabel(const GeoPoint(22.57, 88.36)),
        isNull,
      );
    });

    test('returns null on transport failure', () async {
      when(
        () => client.get<Map<String, dynamic>>(
          '/maps/ola/reverse-geocode',
          queryParameters: any(named: 'queryParameters'),
          parseData: any(named: 'parseData'),
        ),
      ).thenThrow(Exception('offline'));

      expect(
        await RiderMapsService(
          client,
        ).getAreaLabel(const GeoPoint(22.57, 88.36)),
        isNull,
      );
    });
  });
}
