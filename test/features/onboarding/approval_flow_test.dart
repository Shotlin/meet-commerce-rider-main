import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meet_commerce_rider_main/core/config/env.dart';
import 'package:meet_commerce_rider_main/core/config/flavor.dart';
import 'package:meet_commerce_rider_main/core/providers.dart';
import 'package:meet_commerce_rider_main/core/storage/secure_token_store.dart';
import 'package:meet_commerce_rider_main/features/auth/data/auth_api.dart';
import 'package:meet_commerce_rider_main/features/auth/data/auth_repository.dart';
import 'package:meet_commerce_rider_main/features/onboarding/data/documents_api.dart';
import 'package:meet_commerce_rider_main/features/onboarding/domain/rider_document.dart';
import 'package:meet_commerce_rider_main/features/onboarding/presentation/document_upload_screen.dart';
import 'package:meet_commerce_rider_main/features/onboarding/presentation/rider_approval_screen.dart';

/// Phase 5 acceptance: approval / correction experience.
///
/// Matrix: "unapproved rider is routed to approval flow" (covered in
/// `test/app/session_redirect_test.dart`), "document upload works",
/// "rejected document shows reason and supports resubmit". Design §8:
/// calm pending state, per-document state language, correction path.
class _MockAuthApi extends Mock implements AuthApi {}

class _FakeDocumentsApi implements DocumentsApi {
  _FakeDocumentsApi(this.documents);

  final List<RiderDocument> documents;

  @override
  Future<List<RiderDocument>> list() async => documents;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in approval flow test');
}

/// One approved and one rejected document with a reviewer reason;
/// everything else stays missing.
List<RiderDocument> _docsWithRejection() => <RiderDocument>[
  const RiderDocument(
    type: RiderDocumentType.photo,
    status: RiderDocumentStatus.approved,
  ),
  const RiderDocument(
    type: RiderDocumentType.drivingLicense,
    status: RiderDocumentStatus.rejected,
    rejectionReason: 'Photo is blurry — all four corners must be visible',
  ),
];

Future<void> _pumpApproval(
  WidgetTester tester, {
  List<RiderDocument> docs = const <RiderDocument>[],
}) async {
  // Tall surface so the whole six-row checklist is on screen (the default
  // 800×600 test window clips the last rows and `find` would miss them).
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        envProvider.overrideWithValue(Env.forFlavor(AppFlavor.staging)),
        documentsApiProvider.overrideWithValue(_FakeDocumentsApi(docs)),
        authRepositoryProvider.overrideWithValue(
          AuthRepository(api: _MockAuthApi(), tokenStore: InMemoryTokenStore()),
        ),
      ],
      child: const MaterialApp(home: RiderApprovalScreen()),
    ),
  );
  // Initial frame + the post-frame documents refresh.
  await tester.pumpAndSettle();
}

void main() {
  group('RiderApprovalScreen', () {
    testWidgets('renders all six documents in design §8 state language', (
      WidgetTester tester,
    ) async {
      await _pumpApproval(tester, docs: _docsWithRejection());

      // Every canonical document row is present.
      for (final RiderDocumentType type in RiderDocumentType.values) {
        expect(
          find.text(type.displayName),
          findsOneWidget,
          reason: '${type.displayName} row must render',
        );
      }

      // State language (StatusChip renders labels uppercase): approved →
      // APPROVED, rejected → NEEDS CORRECTION, never-uploaded →
      // NOT STARTED (×4).
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.text('NEEDS CORRECTION'), findsOneWidget);
      expect(find.text('NOT STARTED'), findsNWidgets(4));
      expect(find.text('SUBMITTED'), findsNothing);

      // Calm pending header (design §8: no error-red full screen).
      expect(find.text('PENDING APPROVAL'), findsOneWidget);
      expect(find.text('Hi there,'), findsOneWidget);
      expect(
        find.text(
          'Upload the required documents below. Once verified, '
          'you will be able to go online and receive orders.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the reviewer reason on the rejected row (matrix: '
        'rejected document shows reason)', (WidgetTester tester) async {
      await _pumpApproval(tester, docs: _docsWithRejection());

      expect(
        find.text('Photo is blurry — all four corners must be visible'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a rejected row opens the correction upload screen '
        'with the reason and a resubmit action', (WidgetTester tester) async {
      await _pumpApproval(tester, docs: _docsWithRejection());

      await tester.tap(find.text('Driving license'));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentUploadScreen), findsOneWidget);
      expect(find.text('Needs correction'), findsOneWidget);
      expect(
        find.text('Photo is blurry — all four corners must be visible'),
        findsOneWidget,
      );
      expect(
        find.text('Take a new, clear photo and upload it again.'),
        findsOneWidget,
      );
      expect(find.text('Resubmit document'), findsOneWidget);

      // Back returns to the approval checklist (custom arrow_back leading,
      // so tap the icon directly — `pageBack` looks for a Material/Cupertino
      // back button tooltip that this AppBar does not use).
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(RiderApprovalScreen), findsOneWidget);
      expect(find.byType(DocumentUploadScreen), findsNothing);
    });

    testWidgets('an approved document row carries no correction affordance', (
      WidgetTester tester,
    ) async {
      await _pumpApproval(
        tester,
        docs: <RiderDocument>[
          const RiderDocument(
            type: RiderDocumentType.photo,
            status: RiderDocumentStatus.approved,
          ),
        ],
      );

      await tester.tap(find.text('Profile photo'));
      await tester.pumpAndSettle();

      expect(find.text('Needs correction'), findsNothing);
      expect(find.text('Resubmit document'), findsNothing);
      expect(find.text('Upload'), findsOneWidget);
    });
  });
}
