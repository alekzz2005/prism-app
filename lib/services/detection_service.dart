import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Utility for computing angles from custom ML models.
/// This acts as a skeleton ready to integrate a custom trained model.
class AngleComputationUtil {
  // ── Gaussian Smoothing ─────────────────────────────────────────────────
  static const int _smoothingWindow = 11;
  static final List<double> _angleBuffer = [];
  static List<double>? _gaussianKernel;

  static List<double> _getGaussianKernel() {
    if (_gaussianKernel != null) return _gaussianKernel!;
    const double sigma = 3.0; // ~3σ coverage within window
    final int half = _smoothingWindow ~/ 2;
    final kernel = <double>[];
    for (int i = -half; i <= half; i++) {
      kernel.add(math.exp(-(i * i) / (2 * sigma * sigma)));
    }
    _gaussianKernel = kernel;
    return kernel;
  }

  static double smoothAngle(double rawAngle) {
    _angleBuffer.add(rawAngle);
    if (_angleBuffer.length > _smoothingWindow) {
      _angleBuffer.removeAt(0);
    }
    if (_angleBuffer.length < 3) return rawAngle;

    final kernel = _getGaussianKernel();
    final int bufLen = _angleBuffer.length;
    final int kernelOffset = (_smoothingWindow - bufLen) ~/ 2;
    double weightedSum = 0;
    double weightTotal = 0;
    for (int i = 0; i < bufLen; i++) {
      final w = kernel[kernelOffset + i];
      weightedSum += _angleBuffer[i] * w;
      weightTotal += w;
    }
    return weightedSum / weightTotal;
  }

  static void resetSmoothing() {
    _angleBuffer.clear();
  }

  /// Placeholder for custom model integration
  static double computeAbsoluteInjectionAngle(
      CameraImage image, Size imageSize,
      {required String injectionType, int sensorOrientation = 90}) {
    
    // TODO: Pass CameraImage to custom ML model to detect syringe vector.
    // For now, return -1 (undetected).
    double rawSyringeAngle = -1.0; 
    
    if (rawSyringeAngle < 0) return -1;

    double armAngle = 0.0; // Assume IM injection is vertical (0 deg)
    
    double relativeAngle = (rawSyringeAngle - armAngle).abs();
    if (relativeAngle > 180) {
      relativeAngle = 360 - relativeAngle;
    }
    
    if (relativeAngle > 90) {
      relativeAngle = 180 - relativeAngle;
    }

    return smoothAngle(relativeAngle);
  }
}
