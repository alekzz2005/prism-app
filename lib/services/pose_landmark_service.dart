import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseLandmarkService {
  final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream));
  bool _isDetecting = false;

  void dispose() {
    _poseDetector.close();
  }

  /// Processes a single [CameraImage] frame and returns detected poses.
  /// Returns null if a detection is already in progress.
  Future<List<Pose>?> detect(CameraImage image, int sensorOrientation) async {
    if (_isDetecting) return null;
    _isDetecting = true;
    try {
      final inputImage = _inputImageFromCameraImage(image, sensorOrientation);
      if (inputImage == null) return [];
      return await _poseDetector.processImage(inputImage);
    } catch (e, stackTrace) {
      debugPrint('Pose detection error: $e\n$stackTrace');
      return [];
    } finally {
      _isDetecting = false;
    }
  }

  /// Converts a [CameraImage] to an ML Kit [InputImage].
  InputImage? _inputImageFromCameraImage(CameraImage image, int sensorOrientation) {
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation90deg;
    
    Uint8List bytes;
    InputImageFormat fallbackFormat = InputImageFormat.nv21;
    
    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length == 3) {
      // Manual NV21 conversion
      final int width = image.width;
      final int height = image.height;
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final int ySize = width * height;
      final int uvSize = ySize ~/ 2;
      bytes = Uint8List(ySize + uvSize);

      int pos = 0;
      if (yPlane.bytesPerRow == width && (yPlane.bytesPerPixel == null || yPlane.bytesPerPixel == 1)) {
        bytes.setRange(0, ySize, yPlane.bytes);
        pos = ySize;
      } else {
        for (int r = 0; r < height; r++) {
          int rowOffset = r * yPlane.bytesPerRow;
          for (int c = 0; c < width; c++) {
            bytes[pos++] = yPlane.bytes[rowOffset + c * (yPlane.bytesPerPixel ?? 1)];
          }
        }
      }

      final int uvHeight = height ~/ 2;
      final int uvWidth = width ~/ 2;
      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 2;
      for (int r = 0; r < uvHeight; r++) {
        int rowOffset = r * uvRowStride;
        for (int c = 0; c < uvWidth; c++) {
          final int idx = rowOffset + c * uvPixelStride;
          // NV21 is V then U
          bytes[pos++] = vPlane.bytes[idx];
          bytes[pos++] = uPlane.bytes[idx];
        }
      }
    } else {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      bytes = allBytes.done().buffer.asUint8List();
      fallbackFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;
    }

    final inputImageMetadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: fallbackFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
  }

  static ArmLandmark? getElbow(List<Pose> poses, Size imageSize, int sensorOrientation) {
    return _getBestArmPoint(poses, imageSize, sensorOrientation, (arm) => arm.elbow);
  }

  static ArmLandmark? getShoulder(List<Pose> poses, Size imageSize, int sensorOrientation) {
    return _getBestArmPoint(poses, imageSize, sensorOrientation, (arm) => arm.shoulder);
  }

  static ArmLandmark? getWrist(List<Pose> poses, Size imageSize, int sensorOrientation) {
    return _getBestArmPoint(poses, imageSize, sensorOrientation, (arm) => arm.wrist);
  }

  static ArmLandmark? _getBestArmPoint(List<Pose> poses, Size imageSize, int sensorOrientation, ArmLandmark? Function(_PoseArm) selector) {
    final arm = getPatientArm(poses, null, imageSize, sensorOrientation: sensorOrientation);
    return arm != null ? selector(arm) : null;
  }

  static ArmLandmark? _toArmLandmark(PoseLandmark? lm) {
    if (lm == null) return null;
    return ArmLandmark(lm.x, lm.y, lm.likelihood);
  }

  static bool? _lockedIsLeft;
  static Offset? _lockedPatientCenter;
  static ArmLandmark? _smoothedShoulder;
  static ArmLandmark? _smoothedElbow;
  static ArmLandmark? _smoothedWrist;
  static const double _alpha = 0.15; // EMA smoothing factor

  static void resetSmoothing() {
    _lockedIsLeft = null;
    _lockedPatientCenter = null;
    _smoothedShoulder = null;
    _smoothedElbow = null;
    _smoothedWrist = null;
  }

  static ArmLandmark? _applyEMA(ArmLandmark? current, ArmLandmark? previous) {
    if (current == null) return previous;
    if (previous == null) return current;
    // If likelihood drops significantly, trust the previous smoothed position more
    double effectiveAlpha = current.likelihood < 0.5 ? _alpha * 0.5 : _alpha;
    return ArmLandmark(
      current.x * effectiveAlpha + previous.x * (1 - effectiveAlpha),
      current.y * effectiveAlpha + previous.y * (1 - effectiveAlpha),
      current.likelihood * effectiveAlpha + previous.likelihood * (1 - effectiveAlpha),
    );
  }

  /// Finds the patient pose (the one closest to the center of the frame).
  static Pose? getPatientPose(List<Pose> poses, Size imageSize, int sensorOrientation) {
    if (poses.isEmpty) return null;

    double rw = imageSize.width;
    double rh = imageSize.height;
    if (sensorOrientation == 90 || sensorOrientation == 270) {
      rw = imageSize.height;
      rh = imageSize.width;
    }

    Pose? bestPose;
    double bestScore = double.infinity;

    for (var pose in poses) {
      final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
      final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
      final lh = pose.landmarks[PoseLandmarkType.leftHip];
      final rhp = pose.landmarks[PoseLandmarkType.rightHip];

      int count = 0;
      double cx = 0;
      double cy = 0;
      if (ls != null) { cx += ls.x; cy += ls.y; count++; }
      if (rs != null) { cx += rs.x; cy += rs.y; count++; }
      if (lh != null) { cx += lh.x; cy += lh.y; count++; }
      if (rhp != null) { cx += rhp.x; cy += rhp.y; count++; }

      if (count == 0) continue;
      cx /= count;
      cy /= count;

      double ncx = cx / rw;
      double ncy = cy / rh;

      // Distance to screen center (0.5, 0.5)
      double distToCenterSq = (ncx - 0.5) * (ncx - 0.5) + (ncy - 0.5) * (ncy - 0.5);
      double score = distToCenterSq;

      // Lock bonus
      if (_lockedPatientCenter != null) {
        double distToLockSq = (ncx - _lockedPatientCenter!.dx) * (ncx - _lockedPatientCenter!.dx) + 
                              (ncy - _lockedPatientCenter!.dy) * (ncy - _lockedPatientCenter!.dy);
        if (distToLockSq < 0.1) {
          score -= 10.0;
        }
      }

      if (score < bestScore) {
        bestScore = score;
        bestPose = pose;
      }
    }

    if (bestPose != null) {
      final ls = bestPose.landmarks[PoseLandmarkType.leftShoulder];
      final rs = bestPose.landmarks[PoseLandmarkType.rightShoulder];
      final lh = bestPose.landmarks[PoseLandmarkType.leftHip];
      final rhp = bestPose.landmarks[PoseLandmarkType.rightHip];
      int count = 0; double cx = 0, cy = 0;
      if (ls != null) { cx += ls.x; cy += ls.y; count++; }
      if (rs != null) { cx += rs.x; cy += rs.y; count++; }
      if (lh != null) { cx += lh.x; cy += lh.y; count++; }
      if (rhp != null) { cx += rhp.x; cy += rhp.y; count++; }
      if (count > 0) {
        _lockedPatientCenter = Offset((cx/count)/rw, (cy/count)/rh);
      }
    }

    return bestPose;
  }

  /// Extracts the best arm from the Patient Pose.
  static _PoseArm? getPatientArm(List<Pose> poses, dynamic ignoredHand, Size imageSize, {int sensorOrientation = 90}) {
    final patientPose = getPatientPose(poses, imageSize, sensorOrientation);
    if (patientPose == null) return null;

    final leftArm = _PoseArm(
        shoulder: _toArmLandmark(patientPose.landmarks[PoseLandmarkType.leftShoulder]),
        elbow: _toArmLandmark(patientPose.landmarks[PoseLandmarkType.leftElbow]),
        wrist: _toArmLandmark(patientPose.landmarks[PoseLandmarkType.leftWrist]),
        isLeft: true,
    );
    final rightArm = _PoseArm(
        shoulder: _toArmLandmark(patientPose.landmarks[PoseLandmarkType.rightShoulder]),
        elbow: _toArmLandmark(patientPose.landmarks[PoseLandmarkType.rightElbow]),
        wrist: _toArmLandmark(patientPose.landmarks[PoseLandmarkType.rightWrist]),
        isLeft: false,
    );

    double leftLikelihood = (leftArm.shoulder?.likelihood ?? 0) + (leftArm.elbow?.likelihood ?? 0) + (leftArm.wrist?.likelihood ?? 0);
    double rightLikelihood = (rightArm.shoulder?.likelihood ?? 0) + (rightArm.elbow?.likelihood ?? 0) + (rightArm.wrist?.likelihood ?? 0);

    double leftScore = leftLikelihood;
    double rightScore = rightLikelihood;

    if (ignoredHand != null) {
      // Find the arm closest to the active hand!
      double hx = ignoredHand.landmarks[0].x;
      double hy = ignoredHand.landmarks[0].y;
      if (sensorOrientation == 90) {
        hx = 1.0 - ignoredHand.landmarks[0].y;
        hy = ignoredHand.landmarks[0].x;
      } else if (sensorOrientation == 270) {
        hx = ignoredHand.landmarks[0].y;
        hy = 1.0 - ignoredHand.landmarks[0].x;
      }
      // ML Kit Pose landmarks are absolute pixels. We need to normalize them.
      double rw = imageSize.width;
      double rh = imageSize.height;
      if (sensorOrientation == 90 || sensorOrientation == 270) {
        rw = imageSize.height;
        rh = imageSize.width;
      }
      
      double getMinDist(ArmLandmark? s, ArmLandmark? e, ArmLandmark? w) {
        double minDist = double.infinity;
        for (var lm in [s, e, w]) {
          if (lm != null) {
            double dx = (lm.x / rw) - hx;
            double dy = (lm.y / rh) - hy;
            double dist = dx * dx + dy * dy;
            if (dist < minDist) minDist = dist;
          }
        }
        return minDist;
      }

      double distLeft = getMinDist(leftArm.shoulder, leftArm.elbow, leftArm.wrist);
      double distRight = getMinDist(rightArm.shoulder, rightArm.elbow, rightArm.wrist);

      // If hand is significantly closer to one arm, heavily bias towards it
      if (distLeft < distRight - 0.02) {
        leftScore += 10.0;
      } else if (distRight < distLeft - 0.02) {
        rightScore += 10.0;
      }
    }

    // If locked to an arm, prefer it slightly (acts as tie-breaker or fallback)
    if (_lockedIsLeft == true) leftScore += 2.0;
    if (_lockedIsLeft == false) rightScore += 2.0;

    _PoseArm bestArm = leftScore > rightScore ? leftArm : rightArm;
    _lockedIsLeft = bestArm.isLeft;

    _smoothedShoulder = _applyEMA(bestArm.shoulder, _smoothedShoulder);
    _smoothedElbow = _applyEMA(bestArm.elbow, _smoothedElbow);
    _smoothedWrist = _applyEMA(bestArm.wrist, _smoothedWrist);

    return _PoseArm(
      shoulder: _smoothedShoulder,
      elbow: _smoothedElbow,
      wrist: _smoothedWrist,
      isLeft: bestArm.isLeft,
    );
  }
}

class ArmLandmark {
  final double x;
  final double y;
  final double likelihood;
  ArmLandmark(this.x, this.y, this.likelihood);
}

class _PoseArm {
  final ArmLandmark? shoulder;
  final ArmLandmark? elbow;
  final ArmLandmark? wrist;
  final bool isLeft;

  _PoseArm({
    required this.shoulder,
    required this.elbow,
    required this.wrist,
    required this.isLeft,
  });
}
