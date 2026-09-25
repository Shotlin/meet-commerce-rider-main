import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/core/network/api_client.dart';
import 'package:meet_commerce_rider_main/core/network/api_envelope.dart';
import 'package:meet_commerce_rider_main/core/network/api_exception.dart';
import 'package:meet_commerce_rider_main/features/delivery/data/delivery_api.dart';

class _MockApiClient extends Mock implements ApiClient {}

ApiEnvelope<Object?> _envelope({
  required bool success,
  String message = '',
  String? code,
}) {
  return ApiEnvelope<Object?>(success: success, message: message, code: code);
}

void main() {
  late _MockApiClient client;
  late DeliveryApi api;

  setUpAll(() {
    registerFallbackValue(const <String, dynamic>{});
  });

  setUp(() {
    client = _MockApiClient();
    api = DeliveryApi(client);
    when(
      () => client.patch<Object?>(
        any(),
        body: any(named: 'body'),
        parseData: any(named: 'parseData'),
      ),
    ).thenAnswer((_) async => _envelope(success: true, message: 'ok'));
  });

  group('DeliveryApi.toggleOnline — typed backend gates (Big Phase 6)', () {
    test(
      'succeeds silently when the backend acknowledges the toggle',
      () async {
        await api.toggleOnline(true);
        verify(
          () => client.patch<Object?>(
            '/delivery/toggle-online',
            body: <String, dynamic>{'isOnline': true},
            parseData: any(named: 'parseData'),
          ),
        ).called(1);
      },
    );

    test('403 RIDER_NOT_APPROVED -> RiderNotApprovedError', () async {
      when(
        () => client.patch<Object?>(
          any(),
          body: any(named: 'body'),
          parseData: any(named: 'parseData'),
        ),
      ).thenThrow(
        const ApiAuthException(
          'Rider profile is not yet approved',
          statusCode: 403,
          backendCode: 'RIDER_NOT_APPROVED',
        ),
      );

      await expectLater(
        api.toggleOnline(true),
        throwsA(isA<RiderNotApprovedError>()),
      );
    });

    test('403 RIDER_SUSPENDED -> RiderSuspendedError', () async {
      when(
        () => client.patch<Object?>(
          any(),
          body: any(named: 'body'),
          parseData: any(named: 'parseData'),
        ),
      ).thenThrow(
        const ApiAuthException(
          'Rider account is suspended',
          statusCode: 403,
          backendCode: 'RIDER_SUSPENDED',
        ),
      );

      await expectLater(
        api.toggleOnline(true),
        throwsA(isA<RiderSuspendedError>()),
      );
    });

    test('403 with an unrelated code is rethrown untouched', () async {
      when(
        () => client.patch<Object?>(
          any(),
          body: any(named: 'body'),
          parseData: any(named: 'parseData'),
        ),
      ).thenThrow(
        const ApiAuthException(
          'Forbidden',
          statusCode: 403,
          backendCode: 'OTHER_REASON',
        ),
      );

      await expectLater(
        api.toggleOnline(true),
        throwsA(
          isA<ApiAuthException>().having(
            (e) => e.backendCode,
            'backendCode',
            'OTHER_REASON',
          ),
        ),
      );
    });

    test(
      '5xx is rethrown untouched — never disguised as not-approved',
      () async {
        when(
          () => client.patch<Object?>(
            any(),
            body: any(named: 'body'),
            parseData: any(named: 'parseData'),
          ),
        ).thenThrow(
          const ApiServerException(
            'Internal server error',
            statusCode: 500,
            backendCode: 'INTERNAL_ERROR',
          ),
        );

        await expectLater(
          api.toggleOnline(true),
          throwsA(isA<ApiServerException>()),
        );
      },
    );
  });
}
