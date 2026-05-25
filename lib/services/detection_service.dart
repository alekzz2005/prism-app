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



  static double computeAbsoluteInjectionAngle(
      List<Hand> hands, Size imageSize,
      {required String injectionType, int sensorOrientation = 90}) {
    
    double armAngle = 0.0;
    // Fallback for fixed closed position
    // Assume the arm is oriented consistently relative to the camera frame.
    // Per user request: Y-axis (vertical) is 0 degrees, X-axis (horizontal) is 90 degrees.
    if (injectionType == 'IM' || injectionType == 'SubQ') {
      armAngle = 0.0; // Assume arm is vertical in the frame (0 deg)
    } else {
      armAngle = 90.0; // Assume arm is horizontal in the frame (90 deg)
    }

    // 2. Compute Syringe Vector from Hand dart-grip
    // Hand Landmarker returns normalized coordinates (0.0-1.0)
    final rawSyringeAngle = _computeRawDartGripAngle(hands, imageSize, sensorOrientation: sensorOrientation);
    if (rawSyringeAngle < 0) return -1;

    // 3. Compute relative angle
    // The relative angle is the absolute difference between the assumed arm axis and syringe axis.
    double relativeAngle = (rawSyringeAngle - armAngle).abs();
    if (relativeAngle > 180) {
      relativeAngle = 360 - relativeAngle;
    }
    
    // We want the acute angle
    if (relativeAngle > 90) {
      relativeAngle = 180 - relativeAngle;
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

    // _transformPoseCoords removed as Pose is removed

  /// Returns the optimal [base, distal] landmarks for the dart grip vector,
  /// falling back to alternative landmarks if primary ones are hidden.
  static List<Landmark>? getDartGripVector(List<Hand> hands) {
    final wrist = HandLandmarkService.getWrist(hands);
    if (wrist == null) return null;

    final indexTip = HandLandmarkService.getIndexTip(hands);   // L8
    final indexDip = HandLandmarkService.getIndexDip(hands);   // L7
    final indexPip = HandLandmarkService.getIndexPip(hands);   // L6
    final indexMcp = HandLandmarkService.getIndexMcp(hands);   // L5

    // Attempt 1: L7 → L8 (Fingertip vector)
    if (indexDip != null && indexTip != null) return [indexDip, indexTip];

    // Attempt 2: L5 → L8 (Index MCP to Tip - user requested for shallow angles)
    if (indexMcp != null && indexTip != null) return [indexMcp, indexTip];

    // Attempt 3: L5 → L6 (Index proximal phalanx)
    if (indexMcp != null && indexPip != null) return [indexMcp, indexPip];

    // Legacy fallbacks
    if (indexMcp != null) return [wrist, indexMcp];
    if (indexTip != null) return [wrist, indexTip];

    return null;
  }

  /// Raw (un-smoothed) dart-grip angle computation with fallback chain.
  static double _computeRawDartGripAngle(List<Hand> hands, Size imageSize,
      {int sensorOrientation = 90}) {
    final vector = getDartGripVector(hands);
    if (vector == null) return -1;
    return _angleFromLandmarkPair(vector[0], vector[1], imageSize, sensorOrientation);
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
    // Swapped dy and dx: Y-axis is now 0 degrees, X-axis is 90 degrees.
    final radians = math.atan2(dx.abs(), dy.abs());
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
    // Swapped dy and dx: Y-axis is now 0 degrees, X-axis is 90 degrees.
    final radians = math.atan2(dx.abs(), dy.abs());
    return radians * 180 / math.pi;
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

