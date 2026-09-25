import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';

/// Presents a snap-driven modal bottom sheet styled per the rider design
/// system.
///
/// Wraps [showModalBottomSheet] + [DraggableScrollableSheet] with the
/// rider app's preferred snap positions (`[0.20, 0.48, 0.82]`), 28-radius
/// top corners, white background, and a 4 dp top handle. Used by
/// `DeliveryOfferSheet`, the active delivery action sheets, and
/// completion/proof flows.
///
/// The [builder] is given the sheet's [BuildContext]; lay out the sheet
/// body via [AppSheetScaffold] for the standard handle + title + child
/// composition.
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double initialChildSize = 0.48,
  List<double> snapSizes = const <double>[0.20, 0.48, 0.82],
  bool isDismissible = true,
  bool? enableDrag,
}) {
  assert(
    snapSizes.isNotEmpty,
    'snapSizes must contain at least one snap position',
  );

  final List<double> sortedSnaps = List<double>.of(snapSizes)..sort();
  final double minSize = sortedSnaps.first;
  final double maxSize = sortedSnaps.last;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag ?? isDismissible,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.charcoal.withValues(alpha: 0.4),
    builder: (BuildContext sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: initialChildSize.clamp(minSize, maxSize),
        minChildSize: minSize,
        maxChildSize: maxSize,
        snap: true,
        snapSizes: sortedSnaps,
        expand: false,
        builder: (BuildContext draggableContext, ScrollController controller) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppDimensions.sheetRadius),
            ),
            child: ColoredBox(
              color: AppColors.white,
              child: PrimaryScrollController(
                controller: controller,
                child: Builder(builder: builder),
              ),
            ),
          );
        },
      );
    },
  );
}

/// Standard sheet body laying out the rider design system's
/// `[handle] -> optional title row -> child` composition.
///
/// Used as the root widget inside the [showAppBottomSheet] builder so
/// every sheet renders the 4 dp top handle and a consistent title +
/// horizontal padding.
class AppSheetScaffold extends StatelessWidget {
  /// Creates a sheet scaffold rendering the rider sheet handle, an
  /// optional [title] row, and [child] underneath.
  const AppSheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  /// Sheet body rendered below the handle and title row.
  final Widget child;

  /// Optional title rendered to the left of [trailing].
  final String? title;

  /// Optional trailing widget (typically a close button).
  final Widget? trailing;

  /// Padding applied around the title and child block.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SheetHandle(),
        if (title != null || trailing != null)
          Padding(
            padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, 8),
            child: Row(
              children: <Widget>[
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: AppTypography.heading.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                ?trailing,
              ],
            ),
          ),
        // Flexible, not a bare Padding: this Column's own incoming height
        // constraint is bounded (FractionallySizedBox above gives it a
        // tight size matching the sheet's current extent), but a Column
        // only ever passes that bound down to a FLEX child — a plain
        // non-flex child (which `child` would be without this wrapper)
        // always gets an unbounded max height instead, regardless of what
        // this Column itself received. That silently defeats any
        // Flexible/Expanded a caller puts inside `child` to keep, say, an
        // action button on-screen against a variable-length scrollable —
        // the constraint never reaches far enough to bound anything.
        // Wrapping here is what actually lets that work.
        Flexible(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              (title != null || trailing != null) ? 0 : padding.top,
              padding.right,
              padding.bottom,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Renders the standardized 4 dp top handle (40 dp wide, 2-radius).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: SizedBox(
          width: 40,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }
}
