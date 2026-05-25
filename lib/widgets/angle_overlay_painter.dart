import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../services/hand_landmark_service.dart';
import '../services/detection_service.dart';

/// CustomPainter that draws the hand skeleton overlay on top of the camera preview.
/// Highlights the key PRISM landmarks. The syringe axis dynamically matches the 
/// dart grip vector (L7->L8 primarily, with fallbacks for 3-finger shallow grips).
class AngleOverlayPainter extends CustomPainter {
  final List<Hand> hands;
  final Size imageSize;
  final int sensorOrientation;
  final String? injectionType;

  AngleOverlayPainter({
    required this.hands, 
    required this.imageSize,
    this.sensorOrientation = 90,
    this.injectionType,
  });

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
    final indexDipPaint = Paint()..color = Colors.amberAccent;
    final indexTipPaint = Paint()..color = Colors.yellowAccent;

    // L7 → L8 syringe axis (primary — dart grip hand axis)
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

      // Highlight the key PRISM landmarks
      if (lms.length > HandLandmarkIndices.wrist) {
        canvas.drawCircle(_scale(lms[HandLandmarkIndices.wrist], size), 7, wristPaint);
      }

      // Draw the primary syringe axis using the dynamic fallback logic!
      final dartVector = AngleComputationUtil.getDartGripVector([hand]);
      if (dartVector != null) {
        final basePt = _scale(dartVector[0], size);
        final distalPt = _scale(dartVector[1], size);
        
        // Calculate the direction vector
        double dx = distalPt.dx - basePt.dx;
        double dy = distalPt.dy - basePt.dy;
        
        // Ensure the vector always points "forward"
        Offset syringeStart = Offset(basePt.dx - dx * 0.5, basePt.dy - dy * 0.5);
        Offset syringeEnd = Offset(distalPt.dx + dx * 0.5, distalPt.dy + dy * 0.5);
        
        // Draw the syringe barrel line (commented out for production per user request)
        // canvas.drawLine(syringeStart, syringeEnd, syringeAxisPaint);

        // Draw circles at the pivot points (commented out for production)
        // canvas.drawCircle(basePt, 5, indexDipPaint);
        // canvas.drawCircle(distalPt, 5, indexTipPaint);
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
