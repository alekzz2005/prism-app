import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'roboflow_service.dart';

/// Detects the withdrawal angle using the Roboflow model.
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

  /// Updates withdrawal metrics from a pre-computed angle (from RoboflowDetectionService).
  void updateFromAngle({
    required double angle,
    required double insertionAngle,
    required double targetAngle,
    required double tolerance,
  }) {
    if (angle < 0) return;

    _withdrawalAngle = angle;
    _withdrawalScore = RoboflowDetectionService.scoreIMAngle(angle);
    _angularDelta = (insertionAngle - _withdrawalAngle).abs();
    _correspondenceResult = _angularDelta <= tolerance ? 'Matches' : 'Deviates';
  }
}
