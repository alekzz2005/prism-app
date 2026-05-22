import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../services/hand_landmark_service.dart';

/// CustomPainter that draws the hand skeleton overlay on top of the camera preview.
/// Highlights the key PRISM landmarks:
///   L0 (wrist) — cyan, L4 (thumb tip) — amber,
///   L5 (index MCP) — yellow, L9 (middle MCP) — yellow.
/// Primary syringe axis: L0 → midpoint(L5, L9) — hand longitudinal axis.
class AngleOverlayPainter extends CustomPainter {
  final List<Hand> hands;
  final int sensorOrientation;

  AngleOverlayPainter({required this.hands, this.sensorOrientation = 90});

  // MediaPipe hand connections (simplified to the connections relevant
  // to the wrist → index / wrist → thumb paths).
  static const _connections = [
    // Wrist → thumb chain
    [0, 1], [1, 2], [2, 3], [3, 4],
    // Wrist → index chain
    [0, 5], [5, 6], [6, 7], [7, 8],
    // Wrist → middle chain
    [0, 9], [9, 10], [10, 11], [11, 12],
    // Wrist → ring chain
    [0, 13], [13, 14], [14, 15], [15, 16],
    // Wrist → pinky chain
    [0, 17], [17, 18], [18, 19], [19, 20],
    // Palm cross-connections
    [5, 9], [9, 13], [13, 17],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.75)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 6
      ..style = PaintingStyle.fill;

    // Key landmark highlight colours
    final wristPaint = Paint()..color = Colors.cyanAccent;
    final thumbPaint = Paint()..color = Colors.amberAccent;
    final mcpPaint = Paint()..color = Colors.yellowAccent;   // L5, L9

    // L0 → midpoint(L5,L9) syringe axis (primary — dart grip hand axis)
    final syringeAxisPaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    for (final hand in hands) {
      final lms = hand.landmarks;
      if (lms.isEmpty) continue;

      // Draw all connections
      for (final conn in _connections) {
        if (conn[0] < lms.length && conn[1] < lms.length) {
          canvas.drawLine(
            _scale(lms[conn[0]], size),
            _scale(lms[conn[1]], size),
            linePaint,
          );
        }
      }

      // Draw all landmark dots
      for (final lm in lms) {
        canvas.drawCircle(_scale(lm, size), 3, dotPaint);
      }

      // Highlight the key PRISM landmarks (larger dots)
      if (lms.length > HandLandmarkIndices.wrist) {
        canvas.drawCircle(_scale(lms[HandLandmarkIndices.wrist], size), 7, wristPaint);
      }
      if (lms.length > HandLandmarkIndices.thumbTip) {
        canvas.drawCircle(_scale(lms[HandLandmarkIndices.thumbTip], size), 7, thumbPaint);
      }
      // Dart-grip key landmarks (L5, L9 — the finger base pair)
      if (lms.length > HandLandmarkIndices.indexMcp) {
        canvas.drawCircle(_scale(lms[HandLandmarkIndices.indexMcp], size), 7, mcpPaint);
      }
      if (lms.length > HandLandmarkIndices.middleMcp) {
        canvas.drawCircle(_scale(lms[HandLandmarkIndices.middleMcp], size), 7, mcpPaint);
      }

      // Draw the primary syringe axis: L0 → midpoint(L5, L9)
      if (lms.length > HandLandmarkIndices.middleMcp) {
        final wristPt = _scale(lms[HandLandmarkIndices.wrist], size);
        final indexMcpPt = _scale(lms[HandLandmarkIndices.indexMcp], size);
        final middleMcpPt = _scale(lms[HandLandmarkIndices.middleMcp], size);
        final midpoint = Offset(
          (indexMcpPt.dx + middleMcpPt.dx) / 2.0,
          (indexMcpPt.dy + middleMcpPt.dy) / 2.0,
        );
        canvas.drawLine(wristPt, midpoint, syringeAxisPaint);
        // Draw a small diamond at the midpoint target
        canvas.drawCircle(midpoint, 5, mcpPaint);
      }
    }
  }

  /// Scales normalised landmark coordinates (0.0–1.0) to canvas size and handles sensor rotation.
  Offset _scale(Landmark lm, Size canvas) {
    double x = lm.x;
    double y = lm.y;
    if (sensorOrientation == 90) {
      x = 1.0 - lm.y;
      y = lm.x;
    } else if (sensorOrientation == 270) {
      x = lm.y;
      y = 1.0 - lm.x;
    }
    return Offset(x * canvas.width, y * canvas.height);
  }

  @override
  bool shouldRepaint(AngleOverlayPainter old) => old.hands != hands;
}
