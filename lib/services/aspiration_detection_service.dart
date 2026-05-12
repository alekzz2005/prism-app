import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Detects aspiration technique by tracking L4 (thumb tip) displacement.
/// Aspiration is "Correct" when the thumb moves proximally (plunger pull).
class AspirationDetectionService {
  static const double _displacementThreshold = 15.0; // pixels
  static const double _minDurationSeconds = 1.0;

  double? _initialThumbY;
  DateTime? _aspirationStart;
  String _result = 'Not Detected';
  double _duration = 0.0;
  String _smoothness = 'Good';

  List<double> _thumbYHistory = [];

  String get result => _result;
  double get duration => _duration;
  String get smoothness => _smoothness;

  void reset() {
    _initialThumbY = null;
    _aspirationStart = null;
    _result = 'Not Detected';
    _duration = 0.0;
    _smoothness = 'Good';
    _thumbYHistory = [];
  }

  /// Call on each frame. [pose] may be null if detection failed.
  void update(Pose? pose) {
    if (pose == null) return;

    final thumb = pose.landmarks[PoseLandmarkType.rightThumb] ??
        pose.landmarks[PoseLandmarkType.leftThumb];
    if (thumb == null) return;

    _initialThumbY ??= thumb.y;
    _thumbYHistory.add(thumb.y);

    final displacement = (_initialThumbY! - thumb.y).abs();

    if (displacement >= _displacementThreshold) {
      _aspirationStart ??= DateTime.now();
      _duration =
          DateTime.now().difference(_aspirationStart!).inMilliseconds / 1000.0;

      if (_duration >= _minDurationSeconds) {
        _result = 'Correct';
        _smoothness = _computeSmoothness();
      }
    }
  }

  String _computeSmoothness() {
    if (_thumbYHistory.length < 3) return 'Good';
    double totalJitter = 0;
    for (int i = 1; i < _thumbYHistory.length; i++) {
      totalJitter += (_thumbYHistory[i] - _thumbYHistory[i - 1]).abs();
    }
    final avgJitter = totalJitter / (_thumbYHistory.length - 1);
    return avgJitter < 5.0 ? 'Good' : 'Low';
  }

  void markIncorrect() => _result = 'Incorrect';
}
