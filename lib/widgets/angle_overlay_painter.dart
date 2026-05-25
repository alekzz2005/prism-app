import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../services/hand_landmark_service.dart';
import '../services/pose_landmark_service.dart';
import '../services/detection_service.dart';

/// CustomPainter that draws the hand skeleton overlay on top of the camera preview.
/// Highlights the key PRISM landmarks. The syringe axis dynamically matches the 
/// dart grip vector (L7->L8 primarily, with fallbacks for 3-finger shallow grips).
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

  @override
  void paint(Canvas canvas, Size size) {
    // L7 → L8 syringe axis
    final syringeAxisPaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final activeHand = HandLandmarkService.getActiveHand(hands);
    if (activeHand != null) {
      final lms = activeHand.landmarks;
      if (lms.isNotEmpty) {
        // Draw the primary syringe axis using landmarks 7 and 8
        if (lms.length > HandLandmarkIndices.indexTip) {
          final basePt = _scale(lms[HandLandmarkIndices.indexDip], size); // L7
          final distalPt = _scale(lms[HandLandmarkIndices.indexTip], size); // L8
          
          // Calculate the direction vector
          double dx = distalPt.dx - basePt.dx;
          double dy = distalPt.dy - basePt.dy;
          
          // Extend significantly to look like a syringe needle/barrel
          Offset syringeStart = Offset(basePt.dx - dx * 2.0, basePt.dy - dy * 2.0);
          Offset syringeEnd = Offset(distalPt.dx + dx * 2.0, distalPt.dy + dy * 2.0);
          
          // Draw the extended syringe line
          canvas.drawLine(syringeStart, syringeEnd, syringeAxisPaint);
        }
      }
    }

    if (poses.isNotEmpty) {
      final patientArm = PoseLandmarkService.getPatientArm(poses, activeHand, imageSize, sensorOrientation: sensorOrientation);

      ArmLandmark? baseLm;
      ArmLandmark? distalLm;

      if (patientArm != null) {
        baseLm = patientArm.shoulder;
        distalLm = patientArm.elbow;
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

  @override
  bool shouldRepaint(AngleOverlayPainter old) => old.hands != hands || old.poses != poses;

  /// Scales absolute ML Kit Pose coordinates to canvas size.
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
}
