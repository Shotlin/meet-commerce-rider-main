import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Compact centered spinner used when the final layout shape isn't known
/// up-front.
///
/// `LoadingIndicator` renders a [CircularProgressIndicator] with
/// [strokeWidth] of 2 inside a [size] x [size] box, centered in its
/// parent. Per `design.md`, screens prefer shimmering [Skeleton] blocks
/// when the final layout is known and fall back to this spinner only
/// when it isn't (modal action sheets, dialog content, etc.).
class LoadingIndicator extends StatelessWidget {
  /// Creates a centered spinner of [size] dp constrained to [color].
  const LoadingIndicator({super.key, this.size = 24, this.color});

  /// Outer constraint used for both width and height.
  final double size;

  /// Spinner stroke color. Defaults to [AppColors.charcoal].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color resolved = color ?? AppColors.charcoal;
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(resolved),
        ),
      ),
    );
  }
}
