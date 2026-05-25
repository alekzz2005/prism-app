import 'dart:math' as math;

/// Utility for angle smoothing.
/// Angle computation is now handled by RoboflowDetectionService.
/// This class is retained for Gaussian smoothing used by other modules.
class AngleComputationUtil {
  // ── Gaussian Smoothing ─────────────────────────────────────────────────
  static const int _smoothingWindow = 11;
  static final List<double> _angleBuffer = [];
  static List<double>? _gaussianKernel;

  static List<double> _getGaussianKernel() {
    if (_gaussianKernel != null) return _gaussianKernel!;
    const double sigma = 3.0;
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
}
