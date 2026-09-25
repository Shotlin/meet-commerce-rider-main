import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/theme/app_colors.dart';
import 'package:meet_commerce_rider_main/shared/widgets/status_chip.dart';

void main() {
  Future<void> pumpChip(
    WidgetTester tester, {
    required StatusTone tone,
    String label = 'online',
    bool showDot = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatusChip(label: label, tone: tone, showDot: showDot),
          ),
        ),
      ),
    );
  }

  /// Resolves the inner dot Container by filtering on its decoration.
  Container dotContainer(WidgetTester tester) {
    final Iterable<Container> containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.decoration is BoxDecoration);
    return containers.firstWhere(
      (Container c) =>
          (c.decoration! as BoxDecoration).shape == BoxShape.circle,
    );
  }

  group('StatusChip dot color matches tone', () {
    final Map<StatusTone, Color> expected = <StatusTone, Color>{
      StatusTone.online: AppColors.success,
      StatusTone.offline: AppColors.muted,
      StatusTone.pending: AppColors.warning,
      StatusTone.success: AppColors.success,
      StatusTone.danger: AppColors.danger,
      StatusTone.info: AppColors.mapBlue,
      StatusTone.neutral: AppColors.muted,
    };

    for (final MapEntry<StatusTone, Color> entry in expected.entries) {
      testWidgets('${entry.key.name} -> ${entry.value}', (
        WidgetTester tester,
      ) async {
        await pumpChip(tester, tone: entry.key);

        final Container dot = dotContainer(tester);
        final BoxDecoration decoration = dot.decoration! as BoxDecoration;
        expect(decoration.color, entry.value);
      });
    }
  });

  testWidgets('label is rendered uppercased', (WidgetTester tester) async {
    await pumpChip(tester, tone: StatusTone.online, label: 'online');

    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text('online'), findsNothing);
  });

  testWidgets('mixed-case label is uppercased', (WidgetTester tester) async {
    await pumpChip(tester, tone: StatusTone.pending, label: 'Pending');

    expect(find.text('PENDING'), findsOneWidget);
  });

  testWidgets('showDot=false hides the leading dot', (
    WidgetTester tester,
  ) async {
    await pumpChip(tester, tone: StatusTone.online, showDot: false);

    final Iterable<Container> circles = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (Container c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).shape == BoxShape.circle,
        );
    expect(circles, isEmpty);
  });
}
