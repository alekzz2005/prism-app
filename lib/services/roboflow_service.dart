import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// ─── Roboflow Detection Result ──────────────────────────────────────────────
/// Holds the bounding-box centres and dimensions of detected objects.
class RoboflowDetection {
  final double? syringeCx, syringeCy, syringeW, syringeH;
  final double? armCx, armCy, armW, armH;
  final double? needleCx, needleCy, needleW, needleH;
  final int imageWidth;
  final int imageHeight;

  const RoboflowDetection({
    this.syringeCx, this.syringeCy, this.syringeW, this.syringeH,
    this.armCx,     this.armCy,     this.armW,     this.armH,
    this.needleCx,  this.needleCy,  this.needleW,  this.needleH,
    this.imageWidth  = 640,
    this.imageHeight = 480,
  });

  bool get hasSyringe => syringeCx != null;
  bool get hasArm     => armCx != null;
  bool get hasNeedle  => needleCx != null;
}

// ─── Angle Result ───────────────────────────────────────────────────────────
class AngleResult {
  final double angle;             // acute relative angle [0°, 90°]
  final int    score;             // CIT-U 1–5 IM rubric
  final bool   detectionLost;
  final RoboflowDetection? detection; // nullable – carries bbox data for overlay
  final String? frameBase64;      // low-res jpeg base64 for mirroring

  const AngleResult({
    required this.angle,
    required this.score,
    required this.detectionLost,
    this.detection,
    this.frameBase64,
  });

  static const lost = AngleResult(angle: -1, score: 0, detectionLost: true);
}

// ─── Plain data object to pass into compute isolate ─────────────────────────
class RawFrameData {
  final int width;
  final int height;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uRowStride;
  final bool isIOS;
  final int uvPixelStride;
  final int sensorOrientation;

  RawFrameData({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uRowStride,
    required this.uvPixelStride,
    required this.sensorOrientation,
    required this.isIOS,
  });
}

// ─── Service ────────────────────────────────────────────────────────────────
class RoboflowDetectionService {
  // ---- Configuration ----
  static const String _workflowUrl =
      'https://serverless.roboflow.com/veincarmell-pangilinan-cit-edu/workflows/find-syringe-arm-and-needle-v39-logic';

  static const String _apiKey = 'hIFLbCmiFrxFrwcrXe5e';

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
    return _angleBuffer.reduce((a, b) => a + b) / _angleBuffer.length;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PUBLIC API  —  called by CameraNodeScreen every 500 ms
  // ═══════════════════════════════════════════════════════════════════════════

  /// Quickly convert frame data to base64 JPEG without calling the Roboflow API.
  /// Used for WebRTC mirroring during the 'waiting' phase.
  static Future<String?> getFrameBase64(RawFrameData frameData) async {
    final jpegBytes = await compute(_convertFrameDataToJpeg, frameData);
    if (jpegBytes == null || jpegBytes.isEmpty) return null;
    return base64Encode(jpegBytes);
  }

  /// Converts a [CameraImage] (YUV420) to JPEG, sends it to Roboflow,
  /// calculates the relative injection angle, and returns an [AngleResult].
  static Future<AngleResult> detectAngle(CameraImage cameraImage, {int sensorOrientation = 90}) async {
    try {
      // 1. Mock mode
      if (mockMode) return _mockDetect();

      // 2. Extract raw plane data (serializable) from CameraImage
      final isIOS = cameraImage.planes.length == 2;
      final frameData = RawFrameData(
        width:  cameraImage.width,
        height: cameraImage.height,
        yBytes: Uint8List.fromList(cameraImage.planes[0].bytes),
        uBytes: Uint8List.fromList(cameraImage.planes[1].bytes),
        // On iOS (2 planes), the U and V bytes are interleaved in plane 1.
        vBytes: isIOS ? Uint8List.fromList(cameraImage.planes[1].bytes) : Uint8List.fromList(cameraImage.planes[2].bytes),
        yRowStride:   cameraImage.planes[0].bytesPerRow,
        uRowStride:   cameraImage.planes[1].bytesPerRow,
        uvPixelStride: cameraImage.planes[1].bytesPerPixel ?? (isIOS ? 2 : 1),
        sensorOrientation: sensorOrientation,
        isIOS: isIOS,
      );

      // 3. Convert YUV420 → JPEG bytes  (runs in isolate for performance)
      final jpegBytes = await compute(_convertFrameDataToJpeg, frameData);
      if (jpegBytes == null || jpegBytes.isEmpty) {
        debugPrint('[RoboflowService] JPEG conversion returned empty');
        return AngleResult.lost;
      }

      debugPrint('[RoboflowService] JPEG size: ${jpegBytes.length} bytes. Sending to API...');

      // 4. Base64 encode
      final base64Image = base64Encode(jpegBytes);

      final bool isRotated = frameData.sensorOrientation == 90 || frameData.sensorOrientation == 270;
      final int uprightW = isRotated ? frameData.height : frameData.width;
      final int uprightH = isRotated ? frameData.width : frameData.height;
      final int sentW = 640;
      final int sentH = (uprightH * (640.0 / uprightW)).round();

      // 5. Call the Roboflow Workflow API
      final detection = await _callApi(base64Image, sentW, sentH);
      if (detection == null || !detection.hasSyringe || !detection.hasArm) {
        debugPrint('[RoboflowService] Detection missing: syringe=${detection?.hasSyringe}, arm=${detection?.hasArm}');
        return AngleResult(angle: -1, score: 0, detectionLost: true, frameBase64: base64Image);
      }

      debugPrint('[RoboflowService] Detected! syringe=(${detection.syringeCx?.toStringAsFixed(0)},${detection.syringeCy?.toStringAsFixed(0)}) arm=(${detection.armCx?.toStringAsFixed(0)},${detection.armCy?.toStringAsFixed(0)}) needle=${detection.hasNeedle}');

      // 6. Calculate the acute relative angle
      final rawAngle = _computeAngle(detection);
      final smoothed = _smooth(rawAngle);

      // 7. Score using CIT-U IM rubric
      final score = scoreIMAngle(smoothed);

      return AngleResult(
        angle: smoothed, 
        score: score, 
        detectionLost: false, 
        detection: detection,
        frameBase64: base64Image,
      );
    } catch (e, st) {
      debugPrint('[RoboflowService] Error: $e\n$st');
      return AngleResult.lost;
    }
  }

  /// Accepts pre-extracted [TfliteFrameData] (raw YUV bytes already copied
  /// synchronously from CameraImage). This avoids holding a native camera
  /// buffer reference which causes buffer starvation.
  static Future<AngleResult> detectAngleFromFrameData(RawFrameData frameData) async {
    try {
      if (mockMode) return _mockDetect();

      final internalFrame = RawFrameData(
        width: frameData.width,
        height: frameData.height,
        yBytes: frameData.yBytes,
        uBytes: frameData.uBytes,
        vBytes: frameData.vBytes,
        yRowStride: frameData.yRowStride,
        uRowStride: frameData.uRowStride,
        uvPixelStride: frameData.uvPixelStride,
        sensorOrientation: frameData.sensorOrientation,
        isIOS: frameData.isIOS,
      );

      final jpegBytes = await compute(_convertFrameDataToJpeg, internalFrame);
      if (jpegBytes == null || jpegBytes.isEmpty) {
        debugPrint('[RoboflowService] JPEG conversion returned empty');
        return AngleResult.lost;
      }

      debugPrint('[RoboflowService] JPEG size: ${jpegBytes.length} bytes. Sending to API...');

      final base64Image = base64Encode(jpegBytes);

      final bool isRotated = frameData.sensorOrientation == 90 || frameData.sensorOrientation == 270;
      final int uprightW = isRotated ? frameData.height : frameData.width;
      final int uprightH = isRotated ? frameData.width : frameData.height;
      final int sentW = 640;
      final int sentH = (uprightH * (640.0 / uprightW)).round();

      final detection = await _callApi(base64Image, sentW, sentH);
      if (detection == null) {
        debugPrint('[RoboflowService] Detection: null (parser returned nothing)');
        return AngleResult.lost;
      }

      debugPrint('[RoboflowService] Detected! syringe=(${detection.syringeCx?.toStringAsFixed(0)},${detection.syringeCy?.toStringAsFixed(0)}) arm=(${detection.armCx?.toStringAsFixed(0)},${detection.armCy?.toStringAsFixed(0)}) needle=${detection.hasNeedle}');

      // Need BOTH syringe and arm to compute angle
      if (!detection.hasSyringe || !detection.hasArm) {
        debugPrint('[RoboflowService] Partial detection — returning detection for overlay but no angle');
        return AngleResult(angle: -1, score: 0, detectionLost: true, detection: detection);
      }

      final rawAngle = _computeAngle(detection);
      final smoothed = _smooth(rawAngle);
      final score = scoreIMAngle(smoothed);

      return AngleResult(angle: smoothed, score: score, detectionLost: false, detection: detection);
    } catch (e, st) {
      debugPrint('[RoboflowService] Error (fromFrameData): $e\n$st');
      return AngleResult.lost;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  IMAGE CONVERSION  (runs inside compute isolate)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Converts extracted frame data to compressed JPEG bytes.
  /// This runs in a separate isolate via [compute] so the UI stays smooth.
  static Uint8List? _convertFrameDataToJpeg(RawFrameData frame) {
    try {
      final int width  = frame.width;
      final int height = frame.height;
      final image = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex  = y * frame.yRowStride + x;
          final int uvIndex = (y ~/ 2) * frame.uRowStride + (x ~/ 2) * frame.uvPixelStride;

          if (yIndex >= frame.yBytes.length || uvIndex >= frame.uBytes.length) continue;
          
          final int vIndex = frame.isIOS ? uvIndex + 1 : uvIndex;
          if (vIndex >= frame.vBytes.length) continue;

          final int yVal = frame.yBytes[yIndex];
          // Subtract 128 to center around 0
          final int uVal = frame.uBytes[uvIndex] - 128;
          final int vVal = frame.vBytes[vIndex] - 128;

          // Standard YUV to RGB conversion
          int r = (yVal + 1.402 * vVal).round().clamp(0, 255);
          int g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
          int b = (yVal + 1.772 * uVal).round().clamp(0, 255);

          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      // Rotate image based on sensor orientation (usually 90 on Android phones)
      img.Image uprightImage = image;
      if (frame.sensorOrientation == 90) {
        uprightImage = img.copyRotate(image, angle: 90);
      } else if (frame.sensorOrientation == 270) {
        uprightImage = img.copyRotate(image, angle: 270);
      } else if (frame.sensorOrientation == 180) {
        uprightImage = img.copyRotate(image, angle: 180);
      }

      // Resize to 640px max width/height for fast upload
      final resized = img.copyResize(uprightImage, width: 640);

      // JPEG at quality 70
      return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ROBOFLOW API CALL
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<RoboflowDetection?> _callApi(String base64Image, int sentW, int sentH) async {
    try {
      // Use direct Infer API for version 33 to force a low confidence threshold (15%)
      // This allows detecting the syringe even when perfectly horizontal.
      final String inferUrl = 'https://detect.roboflow.com/find-syringe-arm-and-needle/33?api_key=$_apiKey&confidence=15';

      final response = await http.post(
        Uri.parse(inferUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: base64Image,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[RoboflowService] API error: ${response.statusCode}');
        return null;
      }

      debugPrint('[RoboflowService] Response (first 500): ${response.body.substring(0, math.min(500, response.body.length))}');

      return _parseResponses(response.body, sentW, sentH);
    } catch (e) {
      debugPrint('[RoboflowService] API call failed: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ROBUST JSON PARSER  —  handles multiple Roboflow response shapes
  // ═══════════════════════════════════════════════════════════════════════════

  static RoboflowDetection? _parseResponses(String body, int sentW, int sentH) {
    try {
      final decoded = jsonDecode(body);
      int imgW = sentW;
      int imgH = sentH;

      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('image') && decoded['image'] is Map) {
          imgW = (decoded['image']['width'] ?? sentW).toInt();
          imgH = (decoded['image']['height'] ?? sentH).toInt();
        } else if (decoded.containsKey('outputs') && decoded['outputs'] is List && decoded['outputs'].isNotEmpty) {
          final first = decoded['outputs'][0];
          if (first is Map && first.containsKey('image') && first['image'] is Map) {
            imgW = (first['image']['width'] ?? sentW).toInt();
            imgH = (first['image']['height'] ?? sentH).toInt();
          }
        }
      }

      final predictions = _extractPredictions(body);

      if (predictions.isEmpty) {
        debugPrint('[RoboflowService] No predictions found in response.');
        return null;
      }

      debugPrint('[RoboflowService] Found ${predictions.length} combined predictions. Image size: ${imgW}x${imgH}');
      return _mergeAndBuildDetection(predictions, imgW, imgH);
    } catch (e) {
      debugPrint('[RoboflowService] Error parsing responses: $e');
      return null;
    }
  }

  static List<dynamic> _extractPredictions(String body) {
    try {
      final decoded = jsonDecode(body);
      List<dynamic>? predictions;

      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('outputs') && decoded['outputs'] is List) {
          final outputs = decoded['outputs'] as List;
          if (outputs.isNotEmpty && outputs[0] is Map<String, dynamic>) {
            final first = outputs[0] as Map<String, dynamic>;
            if (first.containsKey('predictions')) {
              final preds = first['predictions'];
              if (preds is List) predictions = preds;
              else if (preds is Map && preds.containsKey('predictions')) predictions = preds['predictions'] as List?;
            }
            if (predictions == null && first.containsKey('result')) {
              final result = first['result'];
              if (result is Map && result.containsKey('predictions')) predictions = result['predictions'] as List?;
            }
            if (predictions == null) {
              for (final entry in first.entries) {
                if (entry.value is List && (entry.value as List).isNotEmpty && (entry.value as List)[0] is Map) {
                  predictions = entry.value as List;
                  break;
                }
              }
            }
          }
        }
        if (predictions == null && decoded.containsKey('predictions')) {
          predictions = decoded['predictions'] as List?;
        }
      }
      return predictions ?? [];
    } catch (e) {
      return [];
    }
  }

  static RoboflowDetection? _mergeAndBuildDetection(List<dynamic> predictions, int imgW, int imgH) {
    try {
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

        debugPrint('[RoboflowService]   prediction: class=$className cx=$cx cy=$cy w=$w h=$h');

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
        imageWidth: imgW,
        imageHeight: imgH,
      );
    } catch (e) {
      debugPrint('[RoboflowService] JSON parse error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  VECTOR MATH  —  acute relative angle between syringe and arm
  // ═══════════════════════════════════════════════════════════════════════════

  static double _computeAngle(RoboflowDetection d) {
    // Need both syringe and arm to compute a meaningful angle
    if (!d.hasSyringe || !d.hasArm) return 0;

    // Arm surface direction vector
    double armDx, armDy;
    if ((d.armW ?? 0) > (d.armH ?? 0)) {
      armDx = 1; armDy = 0; // horizontal arm
    } else {
      armDx = 0; armDy = 1; // vertical arm
    }

    // Syringe direction vector
    double syringeDx, syringeDy;
    // (Needle logic removed to improve performance/clean UI per user request)
    // Estimate angle using the syringe bounding box aspect ratio.
    // tan(theta) ≈ height / width.
    // We point the vector towards the arm horizontally (sign of dx).
    double directionX = (d.armCx! - d.syringeCx!).sign;
    if (directionX == 0) directionX = 1.0;
    
    syringeDx = (d.syringeW ?? 1.0) * directionX;
    syringeDy = (d.syringeH ?? 0.0); // Bounding box height gives the vertical tilt

    // Normalise syringe vector
    final mag = math.sqrt(syringeDx * syringeDx + syringeDy * syringeDy);
    if (mag < 1e-6) return 0;
    syringeDx /= mag;
    syringeDy /= mag;

    // cos(θ) = |V_s · V_a| / (|V_s| × |V_a|)
    final dot = (syringeDx * armDx + syringeDy * armDy).abs();
    final cosTheta = dot.clamp(0.0, 1.0);
    final angleRad = math.acos(cosTheta);
    final angleDeg = angleRad * 180.0 / math.pi;

    return angleDeg;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  IM SCORING RUBRIC  (CIT-U 1–5 scale, 90° target ±5° tolerance)
  // ═══════════════════════════════════════════════════════════════════════════

  static int scoreIMAngle(double measuredAngle) {
    final delta = (measuredAngle - 90.0).abs();
    if (delta <= 0.5) return 5; // Near perfect 90.0 degrees
    if (delta <= 5) return 4;
    if (delta <= 10) return 3; // 80-100 degrees passes
    if (delta <= 15) return 2;
    return 1;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MOCK MODE
  // ═══════════════════════════════════════════════════════════════════════════

  static final math.Random _rng = math.Random();

  static AngleResult _mockDetect() {
    final jitter = (_rng.nextDouble() - 0.5) * 8.0;
    final rawAngle = 90.0 + jitter;
    final smoothed = _smooth(rawAngle);
    final score = scoreIMAngle(smoothed);
    return AngleResult(angle: smoothed, score: score, detectionLost: false);
  }
}
