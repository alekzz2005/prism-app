import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'detection_service.dart';

/// Detects the withdrawal angle using the custom model.
/// Compares against the insertion angle to determine correspondence.
class WithdrawalDetectionService {
  double _withdrawalAngle = 0.0;
  int _withdrawalScore = 1;
  String _correspondenceResult = 'Matches';
  double _angularDelta = 0.0;

  double get withdrawalAngle => _withdrawalAngle;
  int get withdrawalScore => _withdrawalScore;
  String get correspondenceResult => _correspondenceResult;
  double get angularDelta => _angularDelta;

  void reset() {
    _withdrawalAngle = 0.0;
    _withdrawalScore = 1;
    _correspondenceResult = 'Matches';
    _angularDelta = 0.0;
  }

  /// Call when student begins withdrawal phase.
  void update(
    CameraImage image, {
    required double insertionAngle,
    required double targetAngle,
    required double tolerance,
    required Size imageSize,
    required String injectionType,
    int sensorOrientation = 90,
  }) {
    // Model-ready placeholder:
    final angle = AngleComputationUtil.computeAbsoluteInjectionAngle(
        image, imageSize, injectionType: injectionType, sensorOrientation: sensorOrientation);
    if (angle < 0) return;

    _withdrawalAngle = angle;
    // We assume scoreAngle is moved to another utility or we can just use a simple delta check
    // since we removed scoreAngle from AngleComputationUtil in the rewrite.
    // For now, simple scoring:
    final mae = (_withdrawalAngle - targetAngle).abs();
    if (mae <= tolerance * 0.4) _withdrawalScore = 5;
    else if (mae <= tolerance * 0.7) _withdrawalScore = 4;
    else if (mae <= tolerance) _withdrawalScore = 3;
    else if (mae <= tolerance * 1.5) _withdrawalScore = 2;
    else _withdrawalScore = 1;

    _angularDelta = (insertionAngle - _withdrawalAngle).abs();
    _correspondenceResult = _angularDelta <= tolerance ? 'Matches' : 'Deviates';
  }
}
