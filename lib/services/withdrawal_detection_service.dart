import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'detection_service.dart';

/// Detects the withdrawal angle using the dart-grip syringe axis (L5→L6).
/// Compares against the insertion angle to determine correspondence.
///
/// Uses the same [AngleComputationUtil.computeDartGripAngle] as insertion
/// so that both phases measure the identical vector, making the
/// angular delta (correspondence) comparison consistent.
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
  /// [hands] — current hand landmarks, [insertionAngle] — recorded insertion angle,
  /// [targetAngle] and [tolerance] from InjectionConfig.
  void update(
    List<Hand> hands, {
    required double insertionAngle,
    required double targetAngle,
    required double tolerance,
    required Size imageSize,
    int sensorOrientation = 90,
  }) {
    final angle = AngleComputationUtil.computeDartGripAngle(hands, imageSize, sensorOrientation: sensorOrientation);
    if (angle < 0) return;

    _withdrawalAngle = angle;
    _withdrawalScore =
        AngleComputationUtil.scoreAngle(angle, targetAngle, tolerance);

    _angularDelta = (insertionAngle - _withdrawalAngle).abs();
    _correspondenceResult = _angularDelta <= tolerance ? 'Matches' : 'Deviates';
  }
}

