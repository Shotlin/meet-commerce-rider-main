import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Pure-Flutter marker glyphs for the active-delivery map.
///
/// The previous Google-Maps backed implementation rasterised three
/// `BitmapDescriptor`s; with `flutter_map` we render the same glyphs
/// as ordinary widgets, sized to logical pixels:
///
/// | role     | size  | fill         | inner glyph                              |
/// |----------|-------|--------------|------------------------------------------|
/// | rider    | 36 dp | black filled | white arrow ([Icons.navigation_rounded]) |
/// | store    | 32 dp | white filled | charcoal storefront ([Icons.storefront]) |
/// | customer | 32 dp | black filled | white home ([Icons.home])                |
///
/// The widget builders are stateless so we don't need to "warm" them
/// in the same sense the old bitmap cache did, but [ensureWarmedFor]
/// and [isWarmedFor] are kept on the public surface so the screen
/// can keep its existing first-frame gating logic.
class MarkerAssets {
  MarkerAssets();

  static const double riderSizeDp = 36;
  static const double otherSizeDp = 32;
  static const double _storeBorderDp = 1;

  /// Set of DPRs that have been "warmed". Widget rendering does not
  /// actually require pre-rasterisation — keeping this around for
  /// API parity with the old bitmap cache.
  static final Set<double> _warmed = <double>{};

  /// Whether [ensureWarmedFor] has been called for [dpr].
  bool isWarmedFor(double dpr) => _warmed.contains(dpr);

  /// No-op placeholder kept for binary compatibility with the old
  /// [BitmapDescriptor]-based call sites. Always resolves on the
  /// next microtask so the screen can `await` it.
  Future<void> ensureWarmedFor(double dpr) async {
    _warmed.add(dpr);
  }

  /// Test seam: clears the warmed-DPR set.
  @visibleForTesting
  static void resetForTesting() {
    _warmed.clear();
  }

  /// Test seam: marks the given [dpr] as warmed without doing any
  /// actual work.
  @visibleForTesting
  void warmForTesting({double dpr = 1}) {
    _warmed.add(dpr);
  }

  /// Rider arrow marker.
  Widget riderMarker() => const _CircleMarker(
    size: riderSizeDp,
    fill: AppColors.black,
    iconColor: AppColors.white,
    icon: Icons.navigation_rounded,
  );

  /// Store storefront marker.
  Widget storeMarker() => const _CircleMarker(
    size: otherSizeDp,
    fill: AppColors.white,
    iconColor: AppColors.charcoal,
    icon: Icons.storefront,
    borderColor: AppColors.black,
    borderWidth: _storeBorderDp,
  );

  /// Customer home marker.
  Widget customerMarker() => const _CircleMarker(
    size: otherSizeDp,
    fill: AppColors.black,
    iconColor: AppColors.white,
    icon: Icons.home,
  );
}

class _CircleMarker extends StatelessWidget {
  const _CircleMarker({
    required this.size,
    required this.fill,
    required this.iconColor,
    required this.icon,
    this.borderColor,
    this.borderWidth = 0,
  });

  final double size;
  final Color fill;
  final Color iconColor;
  final IconData icon;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: borderColor != null && borderWidth > 0
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor, size: size * 0.55),
    );
  }
}
