import 'package:camera/camera.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

/// MediaPipe Hand Landmarker indices used by PRISM.
///
/// Core AGENTS.md landmarks:
///   L0 = Wrist          — base vector point for all angle calculations
///   L4 = Thumb tip      — aspiration plunger displacement tracking
///
/// Dart-grip syringe axis landmarks:
///   In a dart grip the syringe barrel runs along the hand's longitudinal
///   axis. The best proxy is L0 (wrist) → midpoint(L5, L9), i.e. the center
///   of the finger base, which parallels the barrel regardless of finger curl.
///
///   L5  = Index MCP     — base of index finger (lateral grip edge)
///   L9  = Middle MCP    — base of middle finger (center of palm)
///   L8  = Index tip     — legacy fallback (highest RMSE per Lizhe paper)
///   L12 = Middle tip    — fallback distal point
class HandLandmarkIndices {
  static const int wrist = 0;        // L0
  static const int thumbTip = 4;     // L4
  static const int indexMcp = 5;     // L5
  static const int indexPip = 6;     // L6
  static const int indexDip = 7;     // L7
  static const int indexTip = 8;     // L8
  static const int middleMcp = 9;    // L9 — center of finger base
  static const int middleTip = 12;   // L12
  static const int pinkyTip = 20;    // L20
}

/// Wraps the [HandLandmarkerPlugin] lifecycle and provides
/// convenience accessors for the key landmarks.
class HandLandmarkService {
  HandLandmarkerPlugin? _plugin;
  bool _isDetecting = false;

  /// Initialises the MediaPipe Hand Landmarker model.
  /// Call once in [initState] before starting the camera stream.
  void init({
    int numHands = 1,
    double minConfidence = 0.5,
    HandLandmarkerDelegate delegate = HandLandmarkerDelegate.gpu,
  }) {
    _plugin = HandLandmarkerPlugin.create(
      numHands: numHands,
      minHandDetectionConfidence: minConfidence,
      delegate: delegate,
    );
  }

  /// Processes a single [CameraImage] frame and returns detected hands.
  /// Returns an empty list if detection is already in progress (frame skip)
  /// or if the plugin hasn't been initialised.
  List<Hand> detect(CameraImage image, int sensorOrientation) {
    if (_isDetecting || _plugin == null) return [];
    _isDetecting = true;
    try {
      return _plugin!.detect(image, sensorOrientation);
    } catch (e, stackTrace) {
      debugPrint('HandLandmarker detection error: $e\n$stackTrace');
      return [];
    } finally {
      _isDetecting = false;
    }
  }

  // ── Static landmark accessors ──────────────────────────────────────────
  static Offset? _lockedHandCenter;
  static const double _handLockThreshold = 0.15; // Max distance in normalized coordinates

  /// Resets the hand tracking lock.
  static void resetSmoothing() {
    _lockedHandCenter = null;
  }

  /// Finds and locks onto the hand that is likely holding the syringe.
  static Hand? getActiveHand(List<Hand> hands) {
    if (hands.isEmpty) return null;

    if (_lockedHandCenter != null) {
      Hand? bestHand;
      double minD = double.infinity;
      for (var h in hands) {
        if (h.landmarks.isEmpty) continue;
        final center = _getHandCenter(h);
        double d = (center.dx - _lockedHandCenter!.dx) * (center.dx - _lockedHandCenter!.dx) +
                   (center.dy - _lockedHandCenter!.dy) * (center.dy - _lockedHandCenter!.dy);
        if (d < minD) {
          minD = d;
          bestHand = h;
        }
      }
      if (bestHand != null && minD < _handLockThreshold) {
        _lockedHandCenter = _getHandCenter(bestHand);
        return bestHand;
      }
    }

    // Fallback: pick the hand closest to the center of the frame
    Hand? bestHand;
    double minD = double.infinity;
    for (var h in hands) {
      if (h.landmarks.isEmpty) continue;
      final center = _getHandCenter(h);
      double d = (center.dx - 0.5) * (center.dx - 0.5) + (center.dy - 0.5) * (center.dy - 0.5);
      if (d < minD) {
        minD = d;
        bestHand = h;
      }
    }

    if (bestHand != null) {
      _lockedHandCenter = _getHandCenter(bestHand);
    }
    return bestHand;
  }

  static Offset _getHandCenter(Hand hand) {
    double cx = 0;
    double cy = 0;
    for (var lm in hand.landmarks) {
      cx += lm.x;
      cy += lm.y;
    }
    return Offset(cx / hand.landmarks.length, cy / hand.landmarks.length);
  }

  /// Extracts the wrist landmark (L0) from the active hand.
  static Landmark? getWrist(List<Hand> hands) =>
      _getLandmark(hands, HandLandmarkIndices.wrist);

  /// Extracts the thumb-tip landmark (L4) from the active hand.
  static Landmark? getThumbTip(List<Hand> hands) =>
      _getLandmark(hands, HandLandmarkIndices.thumbTip);

  /// Extracts the index-finger MCP landmark (L5) from the active hand.
  static Landmark? getIndexMcp(List<Hand> hands) =>
      _getLandmark(hands, HandLandmarkIndices.indexMcp);

  /// Extracts the index-finger PIP landmark (L6) from the active hand.
  static Landmark? getIndexPip(List<Hand> hands) =>
      _getLandmark(hands, HandLandmarkIndices.indexPip);

  /// Extracts the index-finger DIP landmark (L7) from the active hand.
  static Landmark? getIndexDip(List<Hand> hands) =>
      _getLandmark(hands, HandLandmarkIndices.indexDip);

  /// Extracts the index-fingertip landmark (L8) from the active hand.
  static Landmark? getIndexTip(List<Hand> hands) =>
      _getLandmark(hands, HandLandmarkIndices.indexTip);

  /// Extracts the middle-finger MCP landmark (L9) from the active hand.
  static Landmark? getMiddleMcp(List<Hand> hands) =>
      _getLandmark(hands, HandLandmarkIndices.middleMcp);

  /// Extracts the middle-finger tip landmark (L12) from the active hand.
  static Landmark? getMiddleTip(List<Hand> hands) =>
      _getLandmark(hands, HandLandmarkIndices.middleTip);

  /// Extracts the pinky-finger tip landmark (L20) from the active hand.
  static Landmark? getPinkyTip(List<Hand> hands) =>
      _getLandmark(hands, HandLandmarkIndices.pinkyTip);

  /// Internal helper — returns the landmark at [index] or null.
  static Landmark? _getLandmark(List<Hand> hands, int index) {
    final active = getActiveHand(hands);
    return (active != null && active.landmarks.length > index)
        ? active.landmarks[index]
        : null;
  }

  /// Releases all native resources. Call in [dispose].
  void dispose() {
    _plugin?.dispose();
    _plugin = null;
  }
}
