import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The Freashcut Rider brand mark (the red "FR" rider logo,
/// `assets/branding/brand_logo.png`) — the same mark as the launcher icon,
/// splash and notifications.
///
/// A transparent PNG: the surrounding screen supplies the canvas colour (white
/// per design §7) and no tinting is applied. The mark is wider than tall, so it
/// is fitted (never stretched) inside the [size] box.
class BrandMark extends StatelessWidget {
  /// Creates the brand mark [size] logical pixels wide (height follows the
  /// logo's own proportions), positioned by [alignment] inside its row/column.
  const BrandMark({
    super.key,
    this.size = 96,
    this.alignment = Alignment.center,
  });

  /// Width / height of the logo artwork (926 × 603).
  static const double aspectRatio = 926 / 603;

  /// Asset path of the approved mark.
  static const String assetPath = 'assets/branding/brand_logo.png';

  /// Rendered width in logical pixels.
  final double size;

  /// Where the mark sits when its parent is wider than [size].
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final double height = size / aspectRatio;
    return Align(
      alignment: alignment,
      widthFactor: 1,
      child: Image.asset(
        assetPath,
        width: size,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Freashcut Rider',
        // If the asset ever fails to load (or a test runs without the bundle),
        // degrade to a lettermark instead of the broken-image glyph — the
        // brand screen must never look broken.
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          return SizedBox(
            width: size,
            height: height,
            child: Center(
              child: Text(
                'FR',
                style: TextStyle(
                  fontSize: height * 0.6,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand,
                  height: 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
