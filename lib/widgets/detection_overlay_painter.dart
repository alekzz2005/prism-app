import 'package:flutter/material.dart';
import '../services/roboflow_service.dart';

/// Paints bounding boxes for syringe, arm, and needle detections
/// from Roboflow on top of the camera preview.
class DetectionOverlayPainter extends CustomPainter {
  final RoboflowDetection? detection;
  final Size previewSize; // camera preview size (rotated)

  DetectionOverlayPainter({
    required this.detection,
    required this.previewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detection == null) return;
    final d = detection!;

    // Scale factors from Roboflow image coords → widget coords
    final double scaleX = size.width  / d.imageWidth;
    final double scaleY = size.height / d.imageHeight;

    // ── Arm bounding box (green) ──
    if (d.hasArm) {
      _drawBox(canvas, d.armCx!, d.armCy!, d.armW ?? 100, d.armH ?? 60,
          scaleX, scaleY, const Color(0xFF4ADE80), 'ARM');
    }

    // ── Syringe bounding box (cyan) ──
    if (d.hasSyringe) {
      _drawBox(canvas, d.syringeCx!, d.syringeCy!, d.syringeW ?? 80, d.syringeH ?? 40,
          scaleX, scaleY, const Color(0xFF22D3EE), 'SYRINGE');
    }

    // ── Needle bounding box (yellow) ──
    if (d.hasNeedle) {
      _drawBox(canvas, d.needleCx!, d.needleCy!, d.needleW ?? 30, d.needleH ?? 30,
          scaleX, scaleY, const Color(0xFFFCD34D), 'NEEDLE');
    }

    // ── Syringe→Needle / Syringe→Arm direction line (magenta) ──
    if (d.hasSyringe) {
      final Paint linePaint = Paint()
        ..color = const Color(0xFFFF6BD6)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;

      final from = Offset(d.syringeCx! * scaleX, d.syringeCy! * scaleY);
      final to = d.hasNeedle
          ? Offset(d.needleCx! * scaleX, d.needleCy! * scaleY)
          : d.hasArm
              ? Offset(d.armCx! * scaleX, d.armCy! * scaleY)
              : null;

      if (to != null) {
        // Extend the line beyond the endpoints for visibility
        final dx = to.dx - from.dx;
        final dy = to.dy - from.dy;
        final extended = Offset(to.dx + dx * 0.5, to.dy + dy * 0.5);
        final extendedFrom = Offset(from.dx - dx * 0.3, from.dy - dy * 0.3);

        canvas.drawLine(extendedFrom, extended, linePaint);

        // Draw a small circle at the syringe center
        canvas.drawCircle(from, 5, Paint()..color = const Color(0xFFFF6BD6));
      }
    }
  }

  void _drawBox(Canvas canvas, double cx, double cy, double w, double h,
      double scaleX, double scaleY, Color color, String label) {
    final rect = Rect.fromCenter(
      center: Offset(cx * scaleX, cy * scaleY),
      width:  w * scaleX,
      height: h * scaleY,
    );

    // Box outline
    final boxPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      boxPaint,
    );

    // Semi-transparent fill
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      fillPaint,
    );

    // Label background
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final labelBg = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 6,
        textPainter.width + 10,
        textPainter.height + 6,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(labelBg, Paint()..color = color.withValues(alpha: 0.85));
    textPainter.paint(canvas, Offset(rect.left + 5, rect.top - textPainter.height - 3));
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return detection != oldDelegate.detection;
  }
}
