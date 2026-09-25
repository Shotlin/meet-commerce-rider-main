import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_colors.dart';

/// Skeleton placeholder builders for the Meet Commerce Rider App.
///
/// `Skeleton` is a small namespace of factory constructors that render
/// shimmering [AppColors.offWhite] surfaces while async data is loading.
/// Used by the home dashboard, earnings, history, and profile screens
/// during their pending states. Prefer `LoadingIndicator` only when the
/// final layout shape isn't known up-front.
abstract final class Skeleton {
  /// Creates a rectangular skeleton block of [height], [width], and
  /// [radius].
  static Widget box({
    required double height,
    double width = double.infinity,
    double radius = 12,
  }) {
    return _SkeletonShape(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(radius),
    );
  }

  /// Creates a single-line skeleton, typically used for text rows.
  static Widget line({double height = 14, double width = double.infinity}) {
    return _SkeletonShape(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(6),
    );
  }

  /// Creates a circular skeleton used for avatar / icon placeholders.
  static Widget circle({double size = 40}) {
    return _SkeletonShape(width: size, height: size, shape: BoxShape.circle);
  }
}

/// Internal shimmering surface used by [Skeleton.box], [Skeleton.line],
/// and [Skeleton.circle].
class _SkeletonShape extends StatelessWidget {
  const _SkeletonShape({
    required this.width,
    required this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.offWhite,
      highlightColor: AppColors.white,
      period: const Duration(milliseconds: 1200),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.offWhite,
          borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
          shape: shape,
        ),
      ),
    );
  }
}
