import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The approved FreshCuts brand mark.
///
/// The same asset the customer app ships (`assets/branding/brand_logo.png`,
/// copied from `meet-commerce-mobile-main/assets/icon/brand_logo.png`), so the
/// rider app shows identical branding on splash, login and any future
/// onboarding header.
///
/// Rendered as a plain image: the mark is already a clean on-white asset, so
/// the surrounding screen supplies the canvas colour (white per design §7) and
/// no tinting is applied.
class BrandMark extends StatelessWidget {
  /// Creates the brand mark at [size] logical pixels square.
  const BrandMark({super.key, this.size = 64});

  /// Asset path of the approved mark.
  static const String assetPath = 'assets/branding/brand_logo.png';

  /// Rendered width/height in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: 'FreashCuts',
      // If the asset ever fails to load (or a test runs without the bundle),
      // degrade to a lettermark instead of the broken-image glyph — the brand
      // screen must never look broken.
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              'F',
              style: TextStyle(
                fontSize: size * 0.5,
                fontWeight: FontWeight.w800,
                color: AppColors.brand,
                height: 1,
              ),
            ),
          ),
        );
      },
    );
  }
}
