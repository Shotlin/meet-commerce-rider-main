import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/features/onboarding/domain/rider_document.dart';

void main() {
  group('RiderDocumentType.wire', () {
    test('returns the backend segment allowed by the doc_type constraint', () {
      // The exact set the backend enforces in migration
      // 058_rider_documents_aadhaar_back.sql:
      // ('aadhaar', 'aadhaar_back', 'license', 'vehicle_rc', 'pan', 'photo',
      //  'bank_proof'). A value outside this set is rejected by the DB CHECK
      // constraint, so uploads would fail with a constraint violation.
      expect(RiderDocumentType.photo.wire, 'photo');
      expect(RiderDocumentType.drivingLicense.wire, 'license');
      expect(RiderDocumentType.aadharFront.wire, 'aadhaar');
      expect(RiderDocumentType.aadharBack.wire, 'aadhaar_back');
      expect(RiderDocumentType.vehicleRc.wire, 'vehicle_rc');
      expect(RiderDocumentType.panCard.wire, 'pan');
    });

    test('every wire value is inside the backend doc_type constraint set', () {
      const Set<String> backendAllowed = <String>{
        'aadhaar',
        'aadhaar_back',
        'license',
        'vehicle_rc',
        'pan',
        'photo',
        'bank_proof',
      };

      for (final RiderDocumentType t in RiderDocumentType.values) {
        expect(
          backendAllowed,
          contains(t.wire),
          reason:
              '${t.name} maps to "${t.wire}", which the backend '
              'rider_documents.doc_type CHECK constraint rejects',
        );
      }
    });

    test('every enum value has a unique wire string', () {
      final Set<String> wires = <String>{
        for (final RiderDocumentType t in RiderDocumentType.values) t.wire,
      };
      expect(wires.length, RiderDocumentType.values.length);
    });
  });

  group('RiderDocumentType.displayName', () {
    test('returns sentence-case copy used by the UI', () {
      expect(RiderDocumentType.photo.displayName, 'Profile photo');
      expect(RiderDocumentType.drivingLicense.displayName, 'Driving license');
      expect(RiderDocumentType.aadharFront.displayName, 'Aadhaar front');
      expect(RiderDocumentType.aadharBack.displayName, 'Aadhaar back');
      expect(RiderDocumentType.vehicleRc.displayName, 'Vehicle RC');
      expect(RiderDocumentType.panCard.displayName, 'PAN card');
    });
  });

  group('RiderDocumentType.fromWire round-trip', () {
    test('parse(t.wire) == t for every enum value', () {
      for (final RiderDocumentType t in RiderDocumentType.values) {
        expect(
          RiderDocumentType.fromWire(t.wire),
          t,
          reason: 'fromWire failed to round-trip ${t.wire}',
        );
      }
    });

    test('returns null for unknown wire strings', () {
      expect(RiderDocumentType.fromWire('unknown_doc'), isNull);
      expect(RiderDocumentType.fromWire(''), isNull);
      expect(RiderDocumentType.fromWire(null), isNull);
    });
  });

  group('RiderDocumentStatus.parse (live backend casing)', () {
    test('handles upper-case strings the live backend emits', () {
      expect(RiderDocumentStatus.parse('PENDING'), RiderDocumentStatus.pending);
      expect(
        RiderDocumentStatus.parse('APPROVED'),
        RiderDocumentStatus.approved,
      );
      expect(
        RiderDocumentStatus.parse('REJECTED'),
        RiderDocumentStatus.rejected,
      );
      expect(RiderDocumentStatus.parse('MISSING'), RiderDocumentStatus.missing);
    });

    test('is case-insensitive', () {
      expect(RiderDocumentStatus.parse('pending'), RiderDocumentStatus.pending);
      expect(
        RiderDocumentStatus.parse('Approved'),
        RiderDocumentStatus.approved,
      );
      expect(
        RiderDocumentStatus.parse('rejected'),
        RiderDocumentStatus.rejected,
      );
    });

    test('null, empty, and unknown all map to missing', () {
      expect(RiderDocumentStatus.parse(null), RiderDocumentStatus.missing);
      expect(RiderDocumentStatus.parse(''), RiderDocumentStatus.missing);
      expect(RiderDocumentStatus.parse('  '), RiderDocumentStatus.missing);
      expect(
        RiderDocumentStatus.parse('SUBMITTED'),
        RiderDocumentStatus.missing,
      );
    });
  });

  group('RiderDocument.fromJson', () {
    test('parses a fully-populated camelCase payload', () {
      final RiderDocument doc = RiderDocument.fromJson(<String, dynamic>{
        'type': 'photo',
        'status': 'APPROVED',
        'url': 'https://example.com/photo.jpg',
        'uploadedAt': '2026-05-15T10:00:00Z',
      });
      expect(doc.type, RiderDocumentType.photo);
      expect(doc.status, RiderDocumentStatus.approved);
      expect(doc.url, 'https://example.com/photo.jpg');
      expect(doc.uploadedAt, DateTime.utc(2026, 5, 15, 10, 0, 0));
    });

    test('accepts snake_case alternates: document_type / document_url / '
        'uploaded_at', () {
      final RiderDocument doc = RiderDocument.fromJson(<String, dynamic>{
        'document_type': 'license',
        'status': 'PENDING',
        'document_url': 'https://example.com/dl.jpg',
        'uploaded_at': '2026-05-15T10:00:00Z',
      });
      expect(doc.type, RiderDocumentType.drivingLicense);
      expect(doc.status, RiderDocumentStatus.pending);
      expect(doc.url, 'https://example.com/dl.jpg');
      expect(doc.uploadedAt, isNotNull);
    });

    test(
      'still parses legacy alias wire values written by older app builds',
      () {
        // Rows uploaded before the doc_type values were aligned with the DB
        // constraint may still carry these strings.
        expect(
          RiderDocument.fromJson(<String, dynamic>{
            'type': 'driving_license',
          }).type,
          RiderDocumentType.drivingLicense,
        );
        expect(
          RiderDocument.fromJson(<String, dynamic>{
            'type': 'aadhar_front',
          }).type,
          RiderDocumentType.aadharFront,
        );
        expect(
          RiderDocument.fromJson(<String, dynamic>{'type': 'aadhar_back'}).type,
          RiderDocumentType.aadharBack,
        );
        expect(
          RiderDocument.fromJson(<String, dynamic>{'type': 'pan_card'}).type,
          RiderDocumentType.panCard,
        );
      },
    );

    test('defaults status to missing when absent', () {
      final RiderDocument doc = RiderDocument.fromJson(<String, dynamic>{
        'type': 'pan',
      });
      expect(doc.status, RiderDocumentStatus.missing);
      expect(doc.url, isNull);
    });

    test('throws FormatException for unknown type wire string', () {
      expect(
        () => RiderDocument.fromJson(<String, dynamic>{
          'type': 'unknown_doc',
          'status': 'PENDING',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('captures rejection_reason in either casing', () {
      final RiderDocument camel = RiderDocument.fromJson(<String, dynamic>{
        'type': 'aadhaar',
        'status': 'REJECTED',
        'rejectionReason': 'Blurry',
      });
      expect(camel.rejectionReason, 'Blurry');

      final RiderDocument snake = RiderDocument.fromJson(<String, dynamic>{
        'type': 'aadhaar_back',
        'status': 'REJECTED',
        'rejection_reason': 'Wrong side',
      });
      expect(snake.rejectionReason, 'Wrong side');
    });
  });
}
