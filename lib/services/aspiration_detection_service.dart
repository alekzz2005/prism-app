import 'package:hand_landmarker/hand_landmarker.dart';
import 'hand_landmark_service.dart';

/// Detects aspiration technique by tracking L4 (thumb tip) displacement.
/// Aspiration is "Correct" when the thumb moves proximally (plunger pull).
class AspirationDetectionService {
  static const double _displacementThreshold = 0.025; // normalized units
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

  /// Call on each frame. [hands] is the hand detection result.
  void update(List<Hand> hands, {int sensorOrientation = 90}) {
    final thumb = HandLandmarkService.getThumbTip(hands);
    if (thumb == null) return;

    double thumbY = thumb.y;
    if (sensorOrientation == 90) {
      thumbY = thumb.x;
    } else if (sensorOrientation == 270) {
      thumbY = 1.0 - thumb.x;
    }

    _initialThumbY ??= thumbY;
    _thumbYHistory.add(thumbY);

    final displacement = (_initialThumbY! - thumbY).abs();

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
    return avgJitter < 0.01 ? 'Good' : 'Low';
  }

  void markIncorrect() => _result = 'Incorrect';
}
