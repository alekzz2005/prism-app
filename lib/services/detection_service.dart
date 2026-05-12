import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Utility for computing angles from ML Kit pose landmarks.
/// Uses the L0→L8 convention from AGENTS.md:
///   L0 = wrist, L8 = index fingertip (proxied via rightIndex landmark)
class AngleComputationUtil {
  /// Computes the angle (degrees) of the wrist→index vector
  /// relative to the horizontal axis using atan2.
  static double computeInsertionAngle(Pose pose, {bool useLeft = false}) {
    final wrist = useLeft
        ? pose.landmarks[PoseLandmarkType.leftWrist]
        : pose.landmarks[PoseLandmarkType.rightWrist];
    final index = useLeft
        ? pose.landmarks[PoseLandmarkType.leftIndex]
        : pose.landmarks[PoseLandmarkType.rightIndex];

    if (wrist == null || index == null) return -1;

    // atan2 of wrist→index vector
    final dx = index.x - wrist.x;
    final dy = index.y - wrist.y;
    final radians = math.atan2(dy.abs(), dx.abs());
    return radians * 180 / math.pi;
  }

  /// Computes the angle between two vector segments at a pivot landmark.
  static double angleBetween(
    PoseLandmark a,
    PoseLandmark pivot,
    PoseLandmark b,
  ) {
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

/// Main detection service — wraps PoseDetector lifecycle.
class DetectionService {
  final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );

  bool _isProcessing = false;

  /// Process a raw [InputImage] and return detected poses.
  Future<List<Pose>> detect(InputImage image) async {
    if (_isProcessing) return [];
    _isProcessing = true;
    try {
      return await _detector.processImage(image);
    } finally {
      _isProcessing = false;
    }
  }

  void dispose() => _detector.close();
}
