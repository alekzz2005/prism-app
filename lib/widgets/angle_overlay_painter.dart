import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../services/hand_landmark_service.dart';
import '../services/pose_landmark_service.dart';

/// CustomPainter that draws the hand skeleton overlay on top of the camera preview.
/// Highlights the key PRISM landmarks:
///   L0 (wrist) — cyan, L4 (thumb tip) — amber,
///   L5 (index MCP) — yellow, L9 (middle MCP) — yellow.
/// Primary syringe axis: L0 → midpoint(L5, L9) — hand longitudinal axis.
/// Arm baseline axis: Shoulder → Elbow (from Pose tracking).
class AngleOverlayPainter extends CustomPainter {
  final List<Hand> hands;
  final List<Pose> poses;
  final Size imageSize;
  final int sensorOrientation;
  final String? injectionType;

  AngleOverlayPainter({
    required this.hands, 
    required this.poses,
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

      // Draw the primary syringe axis
      if (lms.length > HandLandmarkIndices.middleMcp) {
        final wristPt = _scale(lms[HandLandmarkIndices.wrist], size);
        final indexMcpPt = _scale(lms[HandLandmarkIndices.indexMcp], size);
        final middleMcpPt = _scale(lms[HandLandmarkIndices.middleMcp], size);
        final midpoint = Offset(
          (indexMcpPt.dx + middleMcpPt.dx) / 2.0,
          (indexMcpPt.dy + middleMcpPt.dy) / 2.0,
        );
        
        Offset axisEnd = wristPt; // Default (fallback)
        
        if (injectionType == 'IM' || injectionType == 'SubQ') {
          // Dart grip: The syringe points perpendicularly outward from the hand axis.
          // Calculate the hand axis vector (wrist -> midpoint)
          double dx = midpoint.dx - wristPt.dx;
          double dy = midpoint.dy - wristPt.dy;
          
          // Compute a perpendicular vector. We swap dx and dy, and negate one.
          // Because the syringe points "forward" from the palm, we just need a visual representation.
          // We'll normalize it to the same length as the hand axis so it looks nice.
          double len = math.sqrt(dx * dx + dy * dy);
          if (len > 0) {
            double pdx = -dy;
            double pdy = dx;
            // The syringe is held near the midpoint (knuckles). We draw it extending outward from there.
            axisEnd = Offset(midpoint.dx + pdx, midpoint.dy + pdy);
            canvas.drawLine(midpoint, axisEnd, syringeAxisPaint);
          }
        } else {
          // Flat grip: Syringe runs along the hand axis
          canvas.drawLine(wristPt, midpoint, syringeAxisPaint);
        }

        // Draw a small diamond at the midpoint target
        canvas.drawCircle(midpoint, 5, mcpPaint);
      }
    }

    // ── Draw Body Baseline Axis (injection-type specific) ─────────────
    // Only the two landmarks relevant to the current injection type:
    //   IM  → Shoulder → Elbow
    //   SubQ → Shoulder → Elbow (upper arm)
    //   IV/ID → Elbow → Wrist (forearm)
    if (poses.isNotEmpty) {
      final patientArm = PoseLandmarkService.getPatientArm(poses, hands.isNotEmpty ? hands.first : null, imageSize, sensorOrientation: sensorOrientation);

      ArmLandmark? baseLm;
      ArmLandmark? distalLm;

      if (patientArm != null) {
        if (injectionType == 'IM' || injectionType == null) {
          baseLm = patientArm.shoulder;
          distalLm = patientArm.elbow;
        } else if (injectionType == 'SubQ') {
          baseLm = patientArm.shoulder;
          distalLm = patientArm.elbow;
        } else if (injectionType == 'ID' || injectionType == 'IV') {
          baseLm = patientArm.elbow;
          distalLm = patientArm.wrist;
        }
      }

      if (baseLm != null && distalLm != null) {
        final axisPaint = Paint()
          ..color = Colors.orangeAccent
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke;

        final jointPaint = Paint()
          ..color = Colors.orangeAccent
          ..style = PaintingStyle.fill;

        final glowPaint = Paint()
          ..color = Colors.orangeAccent.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;

        final basePt = _scalePose(baseLm, size);
        final distalPt = _scalePose(distalLm, size);

        canvas.drawLine(basePt, distalPt, axisPaint);
        canvas.drawCircle(basePt, 7, jointPaint);
        canvas.drawCircle(basePt, 10, glowPaint);
        canvas.drawCircle(distalPt, 7, jointPaint);
        canvas.drawCircle(distalPt, 10, glowPaint);
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

  /// Scales absolute ML Kit Pose coordinates to canvas size.
  ///
  /// ML Kit returns absolute pixel coords in the *rotated* sensor frame.
  /// We simply normalise against the rotated dimensions and scale to canvas.
  Offset _scalePose(ArmLandmark lm, Size canvas) {
    double rw = imageSize.width;
    double rh = imageSize.height;
    if (sensorOrientation == 90 || sensorOrientation == 270) {
      rw = imageSize.height;
      rh = imageSize.width;
    }
    
    double nx = lm.x / rw;
    double ny = lm.y / rh;

    return Offset(nx * canvas.width, ny * canvas.height);
  }

  @override
  bool shouldRepaint(AngleOverlayPainter old) => old.hands != hands || old.poses != poses;
}
