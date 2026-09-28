import 'package:flutter_test/flutter_test.dart';
import 'package:meet_commerce_rider_main/features/delivery/domain/pickup_qr.dart';

void main() {
  const String id = '11111111-2222-4333-8444-555555555555';

  group('parseOrderQr', () {
    test('parses the FreshCuts invoice code', () {
      final ParsedOrderQr? parsed = parseOrderQr(
        'FRESHCUTS-ORDER|FC-KOL-20260928-0001|$id',
      );
      expect(parsed, isNotNull);
      expect(parsed!.orderNumber, 'FC-KOL-20260928-0001');
      expect(parsed.orderId, id);
    });

    test('tolerates surrounding whitespace and upper-case ids', () {
      final ParsedOrderQr? parsed = parseOrderQr(
        '  FRESHCUTS-ORDER|FC-1|${id.toUpperCase()}\n',
      );
      expect(parsed?.orderId, id);
    });

    test('rejects anything that is not a FreshCuts order code', () {
      for (final String? bad in <String?>[
        null,
        '',
        'hello',
        'FRESHCUTS-ORDER|only-two',
        'OTHER|FC-1|$id',
        'FRESHCUTS-ORDER|FC-1|not-a-uuid',
        'FRESHCUTS-ORDER||$id',
        // The retired Bakaloo `version.token.sig` format must not parse.
        '1.abc123.sig456',
      ]) {
        expect(parseOrderQr(bad), isNull, reason: '$bad');
      }
    });
  });
}
