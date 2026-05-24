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

      // Draw the primary syringe axis (L8 -> L20 - Fingertips)
      if (lms.length > HandLandmarkIndices.pinkyTip) {
        final indexTipPt = _scale(lms[HandLandmarkIndices.indexTip], size);
        final pinkyTipPt = _scale(lms[HandLandmarkIndices.pinkyTip], size);
        
        // Calculate the direction vector
        double dx = pinkyTipPt.dx - indexTipPt.dx;
        double dy = pinkyTipPt.dy - indexTipPt.dy;
        
        // Ensure the vector always points "forward" from the index finger towards the pinky
        // The barrel of the syringe lies along this line. Let's draw it from slightly behind index 
        // to slightly past pinky to make it look like a syringe.
        Offset syringeStart = Offset(indexTipPt.dx - dx * 0.2, indexTipPt.dy - dy * 0.2);
        Offset syringeEnd = Offset(pinkyTipPt.dx + dx * 0.5, pinkyTipPt.dy + dy * 0.5);
        
        // Draw the syringe barrel line
        canvas.drawLine(syringeStart, syringeEnd, syringeAxisPaint);

        // Draw a small diamond at the pivot points
        canvas.drawCircle(indexTipPt, 5, mcpPaint);
        canvas.drawCircle(pinkyTipPt, 5, mcpPaint);
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
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke;

        final jointPaint = Paint()
          ..color = Colors.orangeAccent
          ..style = PaintingStyle.fill;

        final basePt = _scalePose(baseLm, size);
        final distalPt = _scalePose(distalLm, size);

        canvas.drawLine(basePt, distalPt, axisPaint);
        canvas.drawCircle(basePt, 5, jointPaint);
        canvas.drawCircle(distalPt, 5, jointPaint);
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
