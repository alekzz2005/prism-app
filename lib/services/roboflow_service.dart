import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// ─── Roboflow Detection Result ──────────────────────────────────────────────
/// Holds the bounding-box centres of detected objects.
class RoboflowDetection {
  final double? syringeCx, syringeCy, syringeW, syringeH;
  final double? armCx, armCy, armW, armH;
  final double? needleCx, needleCy, needleW, needleH;

  const RoboflowDetection({
    this.syringeCx, this.syringeCy, this.syringeW, this.syringeH,
    this.armCx,     this.armCy,     this.armW,     this.armH,
    this.needleCx,  this.needleCy,  this.needleW,  this.needleH,
  });

  bool get hasSyringe => syringeCx != null;
  bool get hasArm     => armCx != null;
  bool get hasNeedle  => needleCx != null;
}

// ─── Angle Result ───────────────────────────────────────────────────────────
class AngleResult {
  final double angle;        // acute relative angle  [0°, 90°]
  final int    score;        // CIT-U 1–5 IM rubric
  final bool   detectionLost;

  const AngleResult({
    required this.angle,
    required this.score,
    required this.detectionLost,
  });

  static const lost = AngleResult(angle: -1, score: 0, detectionLost: true);
}

// ─── Service ────────────────────────────────────────────────────────────────
class RoboflowDetectionService {
  // ---- Configuration ----
  static const String _workflowUrl =
      'https://detect.roboflow.com/infer/workflows/veincarmell-pangilinan-cit-edu/find-syringe-arm-and-needle';

  static const String _apiKey =
      String.fromEnvironment('ROBOFLOW_API_KEY', defaultValue: 'J9jW40Es9tFmhUzmXpMe');

  /// When true, bypasses the API and generates simulated detections.
  static bool mockMode = false;

  // ---- Smoothing ----
  static const int _smoothingWindow = 7;
  static final List<double> _angleBuffer = [];

  static void resetSmoothing() => _angleBuffer.clear();

  static double _smooth(double raw) {
    _angleBuffer.add(raw);
    if (_angleBuffer.length > _smoothingWindow) _angleBuffer.removeAt(0);
    if (_angleBuffer.length < 3) return raw;
    // Simple moving-average (fast, low-jitter)
    return _angleBuffer.reduce((a, b) => a + b) / _angleBuffer.length;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PUBLIC API  —  called by CameraNodeScreen every 500 ms
  // ═══════════════════════════════════════════════════════════════════════════

  /// Converts a [CameraImage] (YUV420) to JPEG, sends it to Roboflow,
  /// calculates the relative injection angle, and returns an [AngleResult].
  static Future<AngleResult> detectAngle(CameraImage cameraImage) async {
    try {
      // 1. Mock mode —  useful for testing without burning API credits
      if (mockMode) return _mockDetect();

      // 2. Convert YUV420 → JPEG bytes  (runs in isolate for performance)
      final jpegBytes = await compute(_convertYuv420ToJpeg, cameraImage);
      if (jpegBytes == null || jpegBytes.isEmpty) return AngleResult.lost;

      // 3. Base64 encode
      final base64Image = base64Encode(jpegBytes);

      // 4. Call the Roboflow Workflow API
      final detection = await _callApi(base64Image);
      if (detection == null || !detection.hasSyringe || !detection.hasArm) {
        return AngleResult.lost;
      }

      // 5. Calculate the acute relative angle
      final rawAngle = _computeAngle(detection);
      final smoothed = _smooth(rawAngle);

      // 6. Score using CIT-U IM rubric
      final score = scoreIMAngle(smoothed);

      return AngleResult(angle: smoothed, score: score, detectionLost: false);
    } catch (e) {
      debugPrint('[RoboflowService] Error: $e');
      return AngleResult.lost;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  IMAGE CONVERSION  (runs inside compute isolate)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Converts a [CameraImage] YUV420 frame to compressed JPEG bytes.
  /// This runs in a separate isolate via [compute] so the UI doesn't jank.
  static Uint8List? _convertYuv420ToJpeg(CameraImage cameraImage) {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;

      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];

      final image = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yPlane.bytesPerRow + x;
          final int uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * (uPlane.bytesPerPixel ?? 1);

          final int yVal = yPlane.bytes[yIndex];
          final int uVal = uPlane.bytes[uvIndex];
          final int vVal = vPlane.bytes[uvIndex];

          // YUV → RGB conversion (BT.601)
          int r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
          int g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).round().clamp(0, 255);
          int b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      // Resize to 640px wide for fast upload (preserving aspect ratio)
      final resized = img.copyResize(image, width: 640);

      // JPEG at quality 70  — good balance of size vs. clarity
      return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
    } catch (e) {
      debugPrint('[RoboflowService] JPEG conversion error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ROBOFLOW API CALL
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<RoboflowDetection?> _callApi(String base64Image) async {
    try {
      final response = await http.post(
        Uri.parse(_workflowUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': _apiKey,
          'inputs': {
            'image': {'type': 'base64', 'value': base64Image},
          },
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[RoboflowService] API error ${response.statusCode}: ${response.body}');
        return null;
      }

      return _parseResponse(response.body);
    } catch (e) {
      debugPrint('[RoboflowService] API call failed: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ROBUST JSON PARSER  —  handles multiple Roboflow response shapes
  // ═══════════════════════════════════════════════════════════════════════════

  static RoboflowDetection? _parseResponse(String body) {
    try {
      final decoded = jsonDecode(body);

      // Shape 1: { "outputs": [ { "predictions": { ... } } ] }
      // Shape 2: { "outputs": [ { "result": { "predictions": [ ... ] } } ] }
      // Shape 3: Root-level { "predictions": [ ... ] }

      List<dynamic>? predictions;

      if (decoded is Map<String, dynamic>) {
        // Try outputs array first
        if (decoded.containsKey('outputs') && decoded['outputs'] is List) {
          final outputs = decoded['outputs'] as List;
          if (outputs.isNotEmpty && outputs[0] is Map<String, dynamic>) {
            final first = outputs[0] as Map<String, dynamic>;

            // Check for "predictions" key directly in outputs[0]
            if (first.containsKey('predictions')) {
              final preds = first['predictions'];
              if (preds is List) {
                predictions = preds;
              } else if (preds is Map && preds.containsKey('predictions')) {
                predictions = preds['predictions'] as List?;
              }
            }

            // Check for "result" → "predictions"
            if (predictions == null && first.containsKey('result')) {
              final result = first['result'];
              if (result is Map && result.containsKey('predictions')) {
                predictions = result['predictions'] as List?;
              }
            }

            // Fallback: iterate all keys in outputs[0] for a list of predictions
            if (predictions == null) {
              for (final value in first.values) {
                if (value is List && value.isNotEmpty && value[0] is Map) {
                  predictions = value;
                  break;
                }
                if (value is Map && value.containsKey('predictions')) {
                  predictions = value['predictions'] as List?;
                  break;
                }
              }
            }
          }
        }

        // Root-level "predictions"
        if (predictions == null && decoded.containsKey('predictions')) {
          predictions = decoded['predictions'] as List?;
        }
      }

      if (predictions == null || predictions.isEmpty) {
        debugPrint('[RoboflowService] No predictions found in response');
        return null;
      }

      // Extract bounding boxes by class name
      double? sCx, sCy, sW, sH;
      double? aCx, aCy, aW, aH;
      double? nCx, nCy, nW, nH;

      for (final pred in predictions) {
        if (pred is! Map<String, dynamic>) continue;

        final className = (pred['class'] ?? pred['class_name'] ?? '').toString().toLowerCase();
        final cx = (pred['x'] ?? pred['cx'])?.toDouble();
        final cy = (pred['y'] ?? pred['cy'])?.toDouble();
        final w  = (pred['width']  ?? pred['w'])?.toDouble();
        final h  = (pred['height'] ?? pred['h'])?.toDouble();

        if (cx == null || cy == null) continue;

        if (className.contains('syringe')) {
          sCx = cx; sCy = cy; sW = w; sH = h;
        } else if (className.contains('arm')) {
          aCx = cx; aCy = cy; aW = w; aH = h;
        } else if (className.contains('needle')) {
          nCx = cx; nCy = cy; nW = w; nH = h;
        }
      }

      return RoboflowDetection(
        syringeCx: sCx, syringeCy: sCy, syringeW: sW, syringeH: sH,
        armCx: aCx, armCy: aCy, armW: aW, armH: aH,
        needleCx: nCx, needleCy: nCy, needleW: nW, needleH: nH,
      );
    } catch (e) {
      debugPrint('[RoboflowService] JSON parse error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  VECTOR MATH  —  acute relative angle between syringe and arm
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculates the acute angle (0°–90°) between the syringe direction and
  /// the arm's surface direction.
  ///
  /// **Arm direction**: if bounding box width > height → horizontal (1,0),
  ///                    else → vertical (0,1).
  ///
  /// **Syringe direction**: if needle detected, vector from syringe centre →
  ///                        needle centre. Otherwise, syringe centre → arm centre.
  static double _computeAngle(RoboflowDetection d) {
    // Arm surface direction vector
    double armDx, armDy;
    if ((d.armW ?? 0) > (d.armH ?? 0)) {
      armDx = 1; armDy = 0; // horizontal arm
    } else {
      armDx = 0; armDy = 1; // vertical arm
    }

    // Syringe direction vector
    double syringeDx, syringeDy;
    if (d.hasNeedle) {
      syringeDx = d.needleCx! - d.syringeCx!;
      syringeDy = d.needleCy! - d.syringeCy!;
    } else {
      syringeDx = d.armCx! - d.syringeCx!;
      syringeDy = d.armCy! - d.syringeCy!;
    }

    // Normalise syringe vector
    final mag = math.sqrt(syringeDx * syringeDx + syringeDy * syringeDy);
    if (mag < 1e-6) return 0; // degenerate
    syringeDx /= mag;
    syringeDy /= mag;

    // cos(θ) = |V_s · V_a| / (|V_s| × |V_a|)   — acute angle via abs dot
    final dot = (syringeDx * armDx + syringeDy * armDy).abs();
    final cosTheta = dot.clamp(0.0, 1.0);
    final angleRad = math.acos(cosTheta);
    final angleDeg = angleRad * 180.0 / math.pi;

    return angleDeg;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  IM SCORING RUBRIC  (CIT-U 1–5 scale, 90° target ±5° tolerance)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Scores the measured angle against the IM target of 90°.
  /// Returns 1–5.
  static int scoreIMAngle(double measuredAngle) {
    final delta = (measuredAngle - 90.0).abs();
    if (delta <= 1) return 5;
    if (delta <= 2) return 4;
    if (delta <= 3) return 3;
    if (delta <= 5) return 2;
    return 1;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MOCK MODE  —  generates realistic simulated detections
  // ═══════════════════════════════════════════════════════════════════════════

  static final math.Random _rng = math.Random();

  static AngleResult _mockDetect() {
    // Simulate a near-perfect 90° angle with slight jitter (±4°)
    final jitter = (_rng.nextDouble() - 0.5) * 8.0; // ±4°
    final rawAngle = 90.0 + jitter;
    final smoothed = _smooth(rawAngle);
    final score = scoreIMAngle(smoothed);
    return AngleResult(angle: smoothed, score: score, detectionLost: false);
  }
}
