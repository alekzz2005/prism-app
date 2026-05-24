import 'dart:math' as math;
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/material.dart';
import 'hand_landmark_service.dart';
import 'pose_landmark_service.dart';

/// Utility for computing angles from MediaPipe Hand Landmarker points.
///
/// **Dart-grip syringe axis** (preferred — per Lizhe EMBC 2024 paper):
///   Primary vector: L5 (Index MCP) → L6 (Index PIP)
///   Fallback:       L5 → L7 (Index DIP), then L0 → L8 (wrist → tip)
///
/// The Lizhe paper validated that L5–L7 have 40% lower RMSE than L8
/// against a VICON reference system (6.7–7.6mm vs 11.7mm).
class AngleComputationUtil {
  // ── Gaussian Smoothing ─────────────────────────────────────────────────
  // Per Lizhe paper Section II.C: Gaussian smoothing reduces MediaPipe jitter.
  // Window = 11 frames (~367ms at 30fps) — balanced for real-time feedback.
  static const int _smoothingWindow = 11;
  static final List<double> _angleBuffer = [];
  static List<double>? _gaussianKernel;

  /// Pre-computes the Gaussian kernel weights for the smoothing window.
  static List<double> _getGaussianKernel() {
    if (_gaussianKernel != null) return _gaussianKernel!;
    const double sigma = 3.0; // ~3σ coverage within window
    final int half = _smoothingWindow ~/ 2;
    final kernel = <double>[];
    for (int i = -half; i <= half; i++) {
      kernel.add(math.exp(-(i * i) / (2 * sigma * sigma)));
    }
    _gaussianKernel = kernel;
    return kernel;
  }

  /// Applies Gaussian smoothing to the angle buffer.
  /// Returns the smoothed angle, or the raw angle if buffer is too small.
  static double _smoothAngle(double rawAngle) {
    _angleBuffer.add(rawAngle);
    if (_angleBuffer.length > _smoothingWindow) {
      _angleBuffer.removeAt(0);
    }
    if (_angleBuffer.length < 3) return rawAngle; // not enough data yet

    final kernel = _getGaussianKernel();
    final int bufLen = _angleBuffer.length;
    // Use as many kernel weights as we have buffer entries, centered.
    final int kernelOffset = (_smoothingWindow - bufLen) ~/ 2;
    double weightedSum = 0;
    double weightTotal = 0;
    for (int i = 0; i < bufLen; i++) {
      final w = kernel[kernelOffset + i];
      weightedSum += _angleBuffer[i] * w;
      weightTotal += w;
    }
    return weightedSum / weightTotal;
  }

  /// Resets the smoothing buffer. Call when starting a new detection
  /// phase or session.
  static void resetSmoothing() {
    _angleBuffer.clear();
  }

  // ── Sensor Orientation Transform ───────────────────────────────────────

  /// Transforms normalised landmark coordinates (0.0–1.0) based on
  /// camera sensor orientation, returning (x, y) in display space.
  static List<double> _transformCoords(
      double rawX, double rawY, int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return [1.0 - rawY, rawX];
      case 270:
        return [rawY, 1.0 - rawX];
      default:
        return [rawX, rawY];
    }
  }

  // ── Dart-Grip Angle (Primary) ──────────────────────────────────────────

  /// Computes the injection angle using the **dart-grip hand axis**.
  ///
  /// In a dart grip the syringe barrel runs along the hand's longitudinal
  /// axis — from the wrist through the center of the palm. The finger
  /// phalanges (L5→L6, etc.) CURL around the barrel, so they do NOT
  /// represent the syringe direction.
  ///
  /// This method uses a landmark fallback chain:
  ///   1. L0 → midpoint(L5, L9)  — wrist to center of finger base (best)
  ///   2. L0 → L9                — wrist to middle MCP
  ///   3. L0 → L5                — wrist to index MCP
  ///   4. L0 → L8                — wrist to index tip (legacy fallback)
  ///
  /// The vector is long (entire palm length) which minimises angular
  /// error from landmark position noise.
  ///
  /// Returns -1 if no usable landmark pair is found.
  /// The returned angle is Gaussian-smoothed to reduce jitter.
  static double computeDartGripAngle(List<Hand> hands, Size imageSize,
      {int sensorOrientation = 90}) {
    final rawAngle =
        _computeRawDartGripAngle(hands, imageSize, sensorOrientation: sensorOrientation);
    if (rawAngle < 0) return -1;
    return _smoothAngle(rawAngle);
  }



  static double computeRelativeInjectionAngle(
      List<Hand> hands, List<Pose> poses, Size imageSize,
      {required String injectionType, int sensorOrientation = 90}) {
    // 1. Compute Arm/Body Baseline Vector from Pose based on injection type
    ArmLandmark? basePoint;
    ArmLandmark? distalPoint;

    final patientArm = PoseLandmarkService.getPatientArm(poses, hands.isNotEmpty ? hands.first : null, imageSize, sensorOrientation: sensorOrientation);

    double armAngle = 0.0;
    bool hasValidArm = false;

    if (patientArm != null) {
      if (injectionType == 'IM') {
        basePoint = patientArm.shoulder;
        distalPoint = patientArm.elbow;
      } else if (injectionType == 'SubQ') {
        basePoint = patientArm.shoulder;
        distalPoint = patientArm.elbow;
      } else if (injectionType == 'ID' || injectionType == 'IV') {
        basePoint = patientArm.elbow;
        distalPoint = patientArm.wrist;
      }

      if (basePoint != null && distalPoint != null) {
        // ML Kit returns absolute pixel coordinates
        // We adjust them based on orientation to match the screen's logical coordinate space
        final baseCoords = _transformPoseCoords(basePoint.x, basePoint.y, imageSize, sensorOrientation);
        final distalCoords = _transformPoseCoords(distalPoint.x, distalPoint.y, imageSize, sensorOrientation);
        
        final armDx = distalCoords[0] - baseCoords[0];
        final armDy = distalCoords[1] - baseCoords[1];
        armAngle = math.atan2(armDy.abs(), armDx.abs()) * 180 / math.pi;
        hasValidArm = true;
      }
    }

    if (!hasValidArm) {
      // Fallback for fixed closed position (close-up camera shots where torso is cut off)
      // Assume the arm is oriented consistently relative to the camera frame.
      if (injectionType == 'IM' || injectionType == 'SubQ') {
        armAngle = 90.0; // Assume arm is vertical in the frame
      } else {
        armAngle = 0.0; // Assume arm is horizontal in the frame
      }
    }

    // 2. Compute Syringe Vector from Hand dart-grip
    // Hand Landmarker returns normalized coordinates (0.0-1.0)
    final rawSyringeAngle = _computeRawDartGripAngle(hands, imageSize, sensorOrientation: sensorOrientation);
    if (rawSyringeAngle < 0) return -1;

    // 3. Compute relative angle
    // The relative angle is the absolute difference between the arm axis and syringe axis.
    double relativeAngle = (rawSyringeAngle - armAngle).abs();
    if (relativeAngle > 180) {
      relativeAngle = 360 - relativeAngle;
    }
    
    // We want the acute angle
    if (relativeAngle > 90) {
      relativeAngle = 180 - relativeAngle;
    }

    if (injectionType == 'IM' || injectionType == 'SubQ') {
      // In Dart Grip, the syringe is held perpendicularly to the hand axis.
      // If the hand is parallel to the arm (0° offset), the needle is perfectly 90° to the arm.
      relativeAngle = (90.0 - relativeAngle).abs();
    }

    return _smoothAngle(relativeAngle);
  }

  static List<double> _transformAbsoluteCoords(double x, double y, Size imageSize, int sensorOrientation) {
    final nx = x / imageSize.width;
    final ny = y / imageSize.height;
    final t = _transformCoords(nx, ny, sensorOrientation);
    
    // Scale by the bounding size based on orientation
    final isPortrait = sensorOrientation == 90 || sensorOrientation == 270;
    final logicalW = isPortrait ? imageSize.height : imageSize.width;
    final logicalH = isPortrait ? imageSize.width : imageSize.height;
    
    return [t[0] * logicalW, t[1] * logicalH];
  }

  static List<double> _transformPoseCoords(double x, double y, Size imageSize, int sensorOrientation) {
    double rw = imageSize.width;
    double rh = imageSize.height;
    if (sensorOrientation == 90 || sensorOrientation == 270) {
      rw = imageSize.height;
      rh = imageSize.width;
    }
    return [x / rw, y / rh];
  }

  /// Raw (un-smoothed) dart-grip angle computation with fallback chain.
  static double _computeRawDartGripAngle(List<Hand> hands, Size imageSize,
      {int sensorOrientation = 90}) {
    final wrist = HandLandmarkService.getWrist(hands);
    if (wrist == null) return -1;

    final indexTip = HandLandmarkService.getIndexTip(hands);   // L8
    final pinkyTip = HandLandmarkService.getPinkyTip(hands);   // L20
    final indexMcp = HandLandmarkService.getIndexMcp(hands);   // L5
    final indexPip = HandLandmarkService.getIndexPip(hands);   // L6

    // Attempt 1: L8 → L20 (Fingertip vector: Index Tip to Pinky Tip)
    // This perfectly traces the syringe barrel resting across the fingers in a dart grip.
    if (indexTip != null && pinkyTip != null) {
      return _angleFromLandmarkPair(indexTip, pinkyTip, imageSize, sensorOrientation);
    }

    // Attempt 2: L5 → L6 (Outer index finger proximal phalanx - fallback for 3-finger grip)
    if (indexMcp != null && indexPip != null) {
      return _angleFromLandmarkPair(indexMcp, indexPip, imageSize, sensorOrientation);
    }

    // Attempt 2: L0 → L5 (Wrist to index MCP - legacy fallback)
    if (indexMcp != null) {
      return _angleFromLandmarkPair(wrist, indexMcp, imageSize, sensorOrientation);
    }

    // Attempt 3: L0 → L8 (Wrist to index tip - legacy fallback)
    if (indexTip != null) {
      return _angleFromLandmarkPair(wrist, indexTip, imageSize, sensorOrientation);
    }

    return -1;
  }

  /// Computes the angle from [wrist] to the midpoint of [a] and [b],
  /// relative to the horizontal axis.
  static double _angleFromWristToMidpoint(
      Landmark wrist, Landmark a, Landmark b, Size imageSize, int sensorOrientation) {
    final wCoords = _transformAbsoluteCoords(wrist.x, wrist.y, imageSize, sensorOrientation);
    final aCoords = _transformAbsoluteCoords(a.x, a.y, imageSize, sensorOrientation);
    final bCoords = _transformAbsoluteCoords(b.x, b.y, imageSize, sensorOrientation);

    // Midpoint of the two distal landmarks
    final midX = (aCoords[0] + bCoords[0]) / 2.0;
    final midY = (aCoords[1] + bCoords[1]) / 2.0;

    final dx = midX - wCoords[0];
    final dy = midY - wCoords[1];
    final radians = math.atan2(dy.abs(), dx.abs());
    return radians * 180 / math.pi;
  }

  /// Computes the angle (degrees) of the vector from [base] to [distal]
  /// relative to the horizontal axis, after sensor orientation transform.
  static double _angleFromLandmarkPair(
      Landmark base, Landmark distal, Size imageSize, int sensorOrientation) {
    final bCoords = _transformAbsoluteCoords(base.x, base.y, imageSize, sensorOrientation);
    final dCoords = _transformAbsoluteCoords(distal.x, distal.y, imageSize, sensorOrientation);

    final dx = dCoords[0] - bCoords[0];
    final dy = dCoords[1] - bCoords[1];
    final radians = math.atan2(dy.abs(), dx.abs());
    return radians * 180 / math.pi;
  }

  static double _computeBodyAngle(
      PoseLandmark base, PoseLandmark distal, Size imageSize, int sensorOrientation) {
    final bCoords = _transformPoseCoords(base.x, base.y, imageSize, sensorOrientation);
    final dCoords = _transformPoseCoords(distal.x, distal.y, imageSize, sensorOrientation);
    final dx = dCoords[0] - bCoords[0];
    final dy = dCoords[1] - bCoords[1];
    return math.atan2(dy, dx) * 180 / math.pi;
  }

  // ── Legacy Angle (Deprecated) ──────────────────────────────────────────

  /// **Deprecated.** Original L0→L8 angle computation.
  /// Kept for backward-compatibility and comparison testing.
  /// Prefer [computeDartGripAngle] for dart-grip syringe positioning.
  @Deprecated('Use computeDartGripAngle instead — L0→L8 has highest RMSE')
  static double computeInsertionAngle(List<Hand> hands,
      {int sensorOrientation = 90}) {
    final wrist = HandLandmarkService.getWrist(hands);
    final index = HandLandmarkService.getIndexTip(hands);

    if (wrist == null || index == null) return -1;

    final wCoords = _transformCoords(wrist.x, wrist.y, sensorOrientation);
    final iCoords = _transformCoords(index.x, index.y, sensorOrientation);

    final dx = iCoords[0] - wCoords[0];
    final dy = iCoords[1] - wCoords[1];
    final radians = math.atan2(dy.abs(), dx.abs());
    return radians * 180 / math.pi;
  }

  // ── Geometric Utilities ────────────────────────────────────────────────

  /// Computes the angle between two vector segments at a pivot landmark.
  static double angleBetween(Landmark a, Landmark pivot, Landmark b) {
    final ax = a.x - pivot.x;
    final ay = a.y - pivot.y;
    final bx = b.x - pivot.x;
    final by = b.y - pivot.y;

    final dot = ax * bx + ay * by;
    final magA = math.sqrt(ax * ax + ay * ay);
    final magB = math.sqrt(bx * bx + by * by);
    if (magA == 0 || magB == 0) return 0;

    final cos = (dot / (magA * magB)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  /// Scores an angle against a target (1–5 based on MAE).
  static int scoreAngle(double measured, double target, double tolerance) {
    final mae = (measured - target).abs();
    if (mae <= tolerance * 0.4) return 5;
    if (mae <= tolerance * 0.7) return 4;
    if (mae <= tolerance) return 3;
    if (mae <= tolerance * 1.5) return 2;
    return 1;
  }
}

