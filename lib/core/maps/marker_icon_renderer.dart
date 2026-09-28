import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// What a map marker represents. Drives its icon and colour so a rider can
/// tell "me" from "the store" from "the customer" at a glance.
enum RiderMarkerKind {
  /// The rider's own live position — a scooter in a dark badge.
  rider,

  /// The rider badge with a direction pointer, used while a reliable travel
  /// heading is known. Rotated at draw time to the heading.
  riderHeading,

  /// The pickup store — a storefront in a red badge.
  store,

  /// The delivery address — a house in a blue badge.
  customer,

  /// Plain coloured dot (no icon).
  dot,
}

/// Badge look for a [RiderMarkerKind] (null for [RiderMarkerKind.dot]).
class RiderMarkerStyle {
  const RiderMarkerStyle({
    required this.icon,
    required this.color,
    this.pointer = false,
  });

  final IconData icon;
  final Color color;

  /// Draws a direction chevron on the badge's top edge (rotate the image to
  /// aim it).
  final bool pointer;

  static RiderMarkerStyle? of(RiderMarkerKind kind) {
    switch (kind) {
      case RiderMarkerKind.rider:
        return const RiderMarkerStyle(
          icon: Icons.two_wheeler_rounded,
          color: Color(0xFF101114),
        );
      case RiderMarkerKind.riderHeading:
        return const RiderMarkerStyle(
          icon: Icons.two_wheeler_rounded,
          color: Color(0xFF101114),
          pointer: true,
        );
      case RiderMarkerKind.store:
        return const RiderMarkerStyle(
          icon: Icons.storefront_rounded,
          color: Color(0xFFE61F2C),
        );
      case RiderMarkerKind.customer:
        return const RiderMarkerStyle(
          icon: Icons.home_rounded,
          color: Color(0xFF2563EB),
        );
      case RiderMarkerKind.dot:
        return null;
    }
  }
}

/// Name a marker image is registered under in the MapLibre style.
String riderMarkerImageName(RiderMarkerKind kind) =>
    'rider-marker-${kind.name}';

/// Draws a round badge (white ring + soft shadow + coloured disc + white
/// glyph) to PNG bytes for `MapLibreMapController.addImage`.
Future<Uint8List> renderRiderMarkerIcon(
  RiderMarkerStyle style, {
  double diameter = 112,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final double shadowPad = diameter * 0.08;
  // The pointer sticks out of the badge; the canvas grows equally on every
  // side so the badge stays at the image centre, which is what the map
  // rotates the symbol around.
  final double pointerLen = style.pointer ? diameter * 0.26 : 0;
  final double total = diameter + (shadowPad + pointerLen) * 2;
  final Offset center = Offset(total / 2, total / 2);
  final double outer = diameter / 2;
  final double ring = diameter * 0.07;

  canvas.drawCircle(
    center + Offset(0, shadowPad * 0.5),
    outer,
    Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowPad),
  );
  if (style.pointer) {
    // Chevron above the ring, pointing "up" (north before rotation).
    final double base = outer * 0.62;
    final Path chevron = Path()
      ..moveTo(center.dx, center.dy - outer - pointerLen)
      ..lineTo(center.dx + base, center.dy - outer * 0.55)
      ..lineTo(center.dx - base, center.dy - outer * 0.55)
      ..close();
    canvas.drawPath(
      chevron.shift(Offset(0, shadowPad * 0.3)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowPad * 0.6),
    );
    canvas.drawPath(chevron, Paint()..color = const Color(0xFF2563EB));
    canvas.drawPath(
      chevron,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = diameter * 0.05
        ..strokeJoin = StrokeJoin.round,
    );
  }
  canvas.drawCircle(center, outer, Paint()..color = Colors.white);
  canvas.drawCircle(center, outer - ring, Paint()..color = style.color);

  final TextPainter glyph = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(style.icon.codePoint),
      style: TextStyle(
        fontFamily: style.icon.fontFamily,
        package: style.icon.fontPackage,
        fontSize: diameter * 0.56,
        color: Colors.white,
      ),
    ),
  )..layout();
  glyph.paint(
    canvas,
    center - Offset(glyph.width / 2, glyph.height / 2),
  );

  final int px = total.ceil();
  final ui.Image image = await recorder.endRecording().toImage(px, px);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
