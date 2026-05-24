import 'dart:math';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'hand_landmark_service.dart';
import 'detection_service.dart';

/// Detects aspiration technique by tracking relative distance between
/// L4 (thumb tip) and the barrel-holding fingers (L8 index, L12 middle).
/// Aspiration is "Correct" when this distance increases (plunger pull).
class AspirationDetectionService {
  static const double _displacementThreshold = 0.025; // 1-handed threshold
  static const double _twoHandDisplacementThreshold = 0.04; // 2-handed threshold
  static const double _minDurationSeconds = 1.0;

  double? _initialDistance;
  double _currentDisplacement = 0.0;

  DateTime? _aspirationStart;
  String _result = 'Not Detected';
  double _duration = 0.0;
  String _smoothness = 'Good';

  List<double> _distanceHistory = [];

  String get result => _result;
  double get duration => _duration;
  String get smoothness => _smoothness;
  double get displacement => _currentDisplacement * 1000;

  bool _isFinished = false;
  bool get isFinished => _isFinished;

  void reset() {
    _initialDistance = null;
    _aspirationStart = null;
    _result = 'Not Detected';
    _duration = 0.0;
    _smoothness = 'Good';
    _currentDisplacement = 0.0;
    _distanceHistory = [];
    _isFinished = false;
  }

  /// Call on each frame. [hands] is the hand detection result.
  void update(List<Hand> hands, double targetAngle, {int sensorOrientation = 90}) {
    if (_isFinished) return;

    if (hands.isEmpty) {
      if (_aspirationStart != null) {
        _isFinished = true;
      }
      return;
    }

    double distance = 0.0;
    bool isTwoHanded = hands.length >= 2;

    if (isTwoHanded) {
      // 2-Handed Technique: Project the plunger hand's movement onto the stable target axis!
      // This prevents false positives from raising hand vertically or dart jitter.
      
      // Calculate unit vector for the target angle (Y-axis is 0 degrees, X-axis is 90 degrees)
      double radians = targetAngle * pi / 180.0;
      double ux = sin(radians); // X component
      double uy = cos(radians); // Y component

      // Use the thumb tip of the second hand (plunger hand)
      final plungerThumb = hands[1].landmarks.length > 4 ? hands[1].landmarks[4] : hands[1].landmarks[0];
      
      // Project the plunger point onto the syringe axis (dot product)
      distance = (plungerThumb.x * ux) + (plungerThumb.y * uy);
    } else {
      // 1-Handed Technique: Measure finger spread on the single hand
      final thumb = HandLandmarkService.getThumbTip(hands);
      final index = HandLandmarkService.getIndexTip(hands);
      final middle = HandLandmarkService.getMiddleTip(hands);

      if (thumb == null || index == null || middle == null) {
        if (_aspirationStart != null) {
          _isFinished = true;
        }
        return;
      }

      // Calculate midpoint of index and middle tips (representing the barrel grip)
      final midX = (index.x + middle.x) / 2;
      final midY = (index.y + middle.y) / 2;

      // Calculate Euclidean distance between thumb and the midpoint
      distance = sqrt(pow(thumb.x - midX, 2) + pow(thumb.y - midY, 2));
    }

    if (_initialDistance == null) {
      _initialDistance = distance;
      return;
    }

    _currentDisplacement = (distance - _initialDistance!).abs();
    _distanceHistory.add(distance);

    // If hand has moved away significantly (e.g. > 0.5) after starting, finish.
    if (_aspirationStart != null && _currentDisplacement > 0.5) {
      _isFinished = true;
      return;
    }

    // Higher threshold for 2-handed to avoid false positives when dragging or raising hand
    final threshold = isTwoHanded ? 0.07 : _displacementThreshold;

    if (_currentDisplacement >= threshold) {
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
    if (_distanceHistory.length < 3) return 'Good';
    double totalJitter = 0;
    for (int i = 1; i < _distanceHistory.length; i++) {
      totalJitter += (_distanceHistory[i] - _distanceHistory[i - 1]).abs();
    }
    final avgJitter = totalJitter / (_distanceHistory.length - 1);
    return avgJitter < 0.01 ? 'Good' : 'Low';
  }

  void markIncorrect() => _result = 'Incorrect';
}
