import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'detection_service.dart';

/// Detects the withdrawal angle (L0→L8 vector on the way out).
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
  /// [pose] — current pose, [insertionAngle] — recorded insertion angle,
  /// [targetAngle] and [tolerance] from InjectionConfig.
  void update(
    Pose pose, {
    required double insertionAngle,
    required double targetAngle,
    required double tolerance,
  }) {
    final angle = AngleComputationUtil.computeInsertionAngle(pose);
    if (angle < 0) return;

    _withdrawalAngle = angle;
    _withdrawalScore =
        AngleComputationUtil.scoreAngle(angle, targetAngle, tolerance);

    _angularDelta = (insertionAngle - _withdrawalAngle).abs();
    _correspondenceResult = _angularDelta <= tolerance ? 'Matches' : 'Deviates';
  }
}
