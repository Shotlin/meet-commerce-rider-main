import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meet_commerce_rider_main/core/theme/app_colors.dart';
import 'package:meet_commerce_rider_main/core/theme/app_dimensions.dart';
import 'package:meet_commerce_rider_main/shared/widgets/app_button.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required AppButtonVariant variant,
    VoidCallback? onPressed,
    bool isLoading = false,
    String label = 'Action',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppButton(
              label: label,
              variant: variant,
              isLoading: isLoading,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }

  Material materialFor(WidgetTester tester) {
    // The button surface is the Material rendered inside AppButton. Resolve
    // it structurally (rather than by colour) so this helper keeps working
    // as variants pick up brand colours.
    return tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AppButton),
            matching: find.byType(Material),
          )
          .first,
    );
  }

  Container surfaceContainerFor(WidgetTester tester) {
    // The bordered container is the Container we built inside the
    // InkWell. Its decoration is a BoxDecoration so we can read the
    // border color back.
    final Iterable<Container> containers = tester.widgetList<Container>(
      find.byType(Container),
    );
    return containers.firstWhere(
      (Container c) => c.decoration is BoxDecoration,
    );
  }

  group('AppButton variants', () {
    testWidgets('primary uses FreshCuts red surface with white label', (
      WidgetTester tester,
    ) async {
      await pumpButton(
        tester,
        variant: AppButtonVariant.primary,
        onPressed: () {},
      );

      final Material material = materialFor(tester);
      expect(material.color, AppColors.brand);

      final Text text = tester.widget<Text>(find.text('Action'));
      expect(text.style?.color, AppColors.white);

      final Container surface = surfaceContainerFor(tester);
      final BoxDecoration decoration = surface.decoration! as BoxDecoration;
      expect(decoration.border, isNull);
    });

    testWidgets('full-width workflow button is 54px tall', (
      WidgetTester tester,
    ) async {
      await pumpButton(
        tester,
        variant: AppButtonVariant.primary,
        onPressed: () {},
      );

      // fullWidth defaults to true, so the design's primary action height
      // applies (design §5: 52–56 px).
      final Size size = tester.getSize(find.byType(AppButton));
      expect(size.height, AppDimensions.buttonHeight);
    });

    testWidgets(
      'secondary uses white surface with charcoal label and 1dp border',
      (WidgetTester tester) async {
        await pumpButton(
          tester,
          variant: AppButtonVariant.secondary,
          onPressed: () {},
        );

        final Material material = materialFor(tester);
        expect(material.color, AppColors.white);

        final Text text = tester.widget<Text>(find.text('Action'));
        expect(text.style?.color, AppColors.charcoal);

        final Container surface = surfaceContainerFor(tester);
        final BoxDecoration decoration = surface.decoration! as BoxDecoration;
        final Border border = decoration.border! as Border;
        expect(border.top.color, AppColors.border);
        expect(border.top.width, 1);
      },
    );

    testWidgets(
      'danger uses error-red surface with white label and no border',
      (WidgetTester tester) async {
        await pumpButton(
          tester,
          variant: AppButtonVariant.danger,
          onPressed: () {},
        );

        final Material material = materialFor(tester);
        expect(material.color, AppColors.danger);

        final Text text = tester.widget<Text>(find.text('Action'));
        expect(text.style?.color, AppColors.white);

        final Container surface = surfaceContainerFor(tester);
        final BoxDecoration decoration = surface.decoration! as BoxDecoration;
        expect(decoration.border, isNull);
      },
    );

    testWidgets('success uses success surface with white label and no border', (
      WidgetTester tester,
    ) async {
      await pumpButton(
        tester,
        variant: AppButtonVariant.success,
        onPressed: () {},
      );

      final Material material = materialFor(tester);
      expect(material.color, AppColors.success);

      final Text text = tester.widget<Text>(find.text('Action'));
      expect(text.style?.color, AppColors.white);

      final Container surface = surfaceContainerFor(tester);
      final BoxDecoration decoration = surface.decoration! as BoxDecoration;
      expect(decoration.border, isNull);
    });
  });

  group('AppButton interaction state', () {
    testWidgets('null onPressed disables the InkWell', (
      WidgetTester tester,
    ) async {
      await pumpButton(
        tester,
        variant: AppButtonVariant.primary,
        // ignore: avoid_redundant_argument_values
        onPressed: null,
      );

      final InkWell ink = tester.widget<InkWell>(find.byType(InkWell));
      expect(ink.onTap, isNull);
    });

    testWidgets('isLoading replaces the label with a 16dp spinner', (
      WidgetTester tester,
    ) async {
      await pumpButton(
        tester,
        variant: AppButtonVariant.primary,
        onPressed: () {},
        isLoading: true,
      );

      expect(find.text('Action'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // The spinner is constrained to a 16x16 box.
      final SizedBox box = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(CircularProgressIndicator),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(box.height, 16);
      expect(box.width, 16);

      // While loading, taps are inert.
      final InkWell ink = tester.widget<InkWell>(find.byType(InkWell));
      expect(ink.onTap, isNull);
    });

    testWidgets('tapping a primary button fires onPressed', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpButton(
        tester,
        variant: AppButtonVariant.primary,
        onPressed: () => taps++,
      );

      await tester.tap(find.byType(AppButton));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('tap target is at least 48 dp tall', (
      WidgetTester tester,
    ) async {
      await pumpButton(
        tester,
        variant: AppButtonVariant.primary,
        onPressed: () {},
      );

      final Size size = tester.getSize(find.byType(AppButton));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });
}
