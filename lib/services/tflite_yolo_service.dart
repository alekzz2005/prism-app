import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

// ─── YOLO Detection Result ──────────────────────────────────────────────────
class YoloDetection {
  final double? syringeCx, syringeCy, syringeW, syringeH;
  final double? armCx, armCy, armW, armH;
  final double? needleCx, needleCy, needleW, needleH;
  final int imageWidth;
  final int imageHeight;

  const YoloDetection({
    this.syringeCx, this.syringeCy, this.syringeW, this.syringeH,
    this.armCx,     this.armCy,     this.armW,     this.armH,
    this.needleCx,  this.needleCy,  this.needleW,  this.needleH,
    this.imageWidth  = 640,
    this.imageHeight = 640,
  });

  bool get hasSyringe => syringeCx != null;
  bool get hasArm     => armCx != null;
  bool get hasNeedle  => needleCx != null;
}

// ─── Angle Result ───────────────────────────────────────────────────────────
class AngleResult {
  final double angle;
  final int    score;
  final bool   detectionLost;
  final YoloDetection? detection;

  const AngleResult({
    required this.angle,
    required this.score,
    required this.detectionLost,
    this.detection,
  });

  static const lost = AngleResult(angle: -1, score: 0, detectionLost: true);
}

// ─── Frame Data for Isolate ────────────────────────────────────────────────
class _FrameData {
  final int width;
  final int height;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uRowStride;
  final int uvPixelStride;
  final int sensorOrientation;

  _FrameData({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uRowStride,
    required this.uvPixelStride,
    required this.sensorOrientation,
  });
}

// ─── Bounding Box ───────────────────────────────────────────────────────────
class _BBox {
  final double cx, cy, w, h, prob;
  final int classId;
  _BBox(this.cx, this.cy, this.w, this.h, this.prob, this.classId);
}

// ─── Service ────────────────────────────────────────────────────────────────
class TFLiteYoloService {
  static Interpreter? _interpreter;
  static bool _isProcessing = false;

  static const int _smoothingWindow = 7;
  static final List<double> _angleBuffer = [];
  
  static const int _inputSize = 640;
  static const double _confThreshold = 0.25;
  static const double _iouThreshold = 0.45;

  static Future<void> initialize() async {
    if (_interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/model/arm_syringe_needle.tflite');
      debugPrint('[TFLiteYoloService] Loaded TFLite model successfully.');
    } catch (e) {
      debugPrint('[TFLiteYoloService] Failed to load model: $e');
    }
  }

  static void resetSmoothing() => _angleBuffer.clear();

  static double _smooth(double raw) {
    _angleBuffer.add(raw);
    if (_angleBuffer.length > _smoothingWindow) _angleBuffer.removeAt(0);
    if (_angleBuffer.length < 3) return raw;
    return _angleBuffer.reduce((a, b) => a + b) / _angleBuffer.length;
  }

  static Future<AngleResult> detectAngle(CameraImage cameraImage, int sensorOrientation) async {
    if (_interpreter == null) return AngleResult.lost;
    if (_isProcessing) return AngleResult.lost;
    
    _isProcessing = true;
    try {
      final frameData = _FrameData(
        width:  cameraImage.width,
        height: cameraImage.height,
        yBytes: Uint8List.fromList(cameraImage.planes[0].bytes),
        uBytes: Uint8List.fromList(cameraImage.planes[1].bytes),
        vBytes: Uint8List.fromList(cameraImage.planes[2].bytes),
        yRowStride:   cameraImage.planes[0].bytesPerRow,
        uRowStride:   cameraImage.planes[1].bytesPerRow,
        uvPixelStride: cameraImage.planes[1].bytesPerPixel ?? 1,
        sensorOrientation: sensorOrientation,
      );

      // Convert YUV to normalized RGB Float32 tensor [1, 640, 640, 3] in Isolate
      final inputTensor = await compute(_preprocessFrame, frameData);
      if (inputTensor == null) return AngleResult.lost;

      // Output shape for YOLOv8 is typically [1, 7, 8400]
      var outputShape = _interpreter!.getOutputTensor(0).shape; // [1, 7, 8400]
      var output = List.generate(
        outputShape[0],
        (_) => List.generate(
          outputShape[1],
          (_) => List.filled(outputShape[2], 0.0),
        ),
      );

      // Run inference
      _interpreter!.run(inputTensor, output);

      // Post-process in isolate
      final detection = await compute(_postProcess, output[0]);
      
      print('[TFLiteYoloService] Detection result: syringe=${detection.hasSyringe}, arm=${detection.hasArm}, needle=${detection.hasNeedle}');

      if (!detection.hasSyringe || !detection.hasArm) {
        return AngleResult.lost;
      }

      final rawAngle = _computeAngle(detection);
      final smoothed = _smooth(rawAngle);
      final score = scoreIMAngle(smoothed);

      return AngleResult(angle: smoothed, score: score, detectionLost: false, detection: detection);
    } catch (e, st) {
      debugPrint('[TFLiteYoloService] Error: $e\n$st');
      return AngleResult.lost;
    } finally {
      _isProcessing = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  IMAGE PREPROCESSING (Runs in Isolate)
  // ═══════════════════════════════════════════════════════════════════════════
  static List<List<List<List<double>>>>? _preprocessFrame(_FrameData frame) {
    try {
      final int width  = frame.width;
      final int height = frame.height;
      final image = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex  = y * frame.yRowStride + x;
          final int uvIndex = (y ~/ 2) * frame.uRowStride + (x ~/ 2) * frame.uvPixelStride;

          if (yIndex >= frame.yBytes.length || uvIndex >= frame.uBytes.length || uvIndex >= frame.vBytes.length) continue;

          final int yVal = frame.yBytes[yIndex];
          final int uVal = frame.uBytes[uvIndex];
          final int vVal = frame.vBytes[uvIndex];

          int r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
          int g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).round().clamp(0, 255);
          int b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      // Rotate image based on sensor orientation so it's upright for YOLO
      var rotated = image;
      if (frame.sensorOrientation != 0) {
        rotated = img.copyRotate(image, angle: frame.sensorOrientation);
      }

      // Resize to 640x640
      final resized = img.copyResize(rotated, width: _inputSize, height: _inputSize);

      // Create Float32 tensor [1, 640, 640, 3] normalized to [0, 1]
      var tensor = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (y) => List.generate(
            _inputSize,
            (x) {
              final pixel = resized.getPixel(x, y);
              return [
                pixel.r / 255.0,
                pixel.g / 255.0,
                pixel.b / 255.0,
              ];
            },
          ),
        ),
      );

      return tensor;
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  POSTPROCESSING (Runs in Isolate)
  // ═══════════════════════════════════════════════════════════════════════════
  static YoloDetection _postProcess(List<List<double>> output) {
    int numRows = output.length;
    int numCols = output[0].length;
    
    bool isTransposed = false;
    if (numRows > numCols) {
      isTransposed = true;
    }

    int numAnchors = isTransposed ? numRows : numCols;
    int numFeatures = isTransposed ? numCols : numRows;

    List<_BBox> boxes = [];

    for (int i = 0; i < numAnchors; i++) {
      double maxProb = 0.0;
      int bestClass = -1;
      
      for (int c = 4; c < numFeatures; c++) {
        final prob = isTransposed ? output[i][c] : output[c][i];
        if (prob > maxProb) {
          maxProb = prob;
          bestClass = c - 4; // 0=arm, 1=needle, 2=syringe
        }
      }

      if (maxProb > _confThreshold) {
        double cx = isTransposed ? output[i][0] : output[0][i];
        double cy = isTransposed ? output[i][1] : output[1][i];
        double w  = isTransposed ? output[i][2] : output[2][i];
        double h  = isTransposed ? output[i][3] : output[3][i];

        // If coordinates are normalized (0..1), scale them up to absolute pixel values
        if (w <= 1.1 && h <= 1.1) {
          cx *= _inputSize;
          cy *= _inputSize;
          w  *= _inputSize;
          h  *= _inputSize;
        }

        boxes.add(_BBox(cx, cy, w, h, maxProb, bestClass));
      }
    }

    boxes = _applyNms(boxes);
    
    print('[TFLiteYoloService] Total bounding boxes after NMS: ${boxes.length}');

    double? sCx, sCy, sW, sH;
    double? aCx, aCy, aW, aH;
    double? nCx, nCy, nW, nH;

    for (var b in boxes) {
      print('[TFLiteYoloService] Box: class=${b.classId}, prob=${b.prob.toStringAsFixed(2)}, cx=${b.cx.toStringAsFixed(1)}, cy=${b.cy.toStringAsFixed(1)}');
      if (b.classId == 0 && aCx == null) {
        aCx = b.cx; aCy = b.cy; aW = b.w; aH = b.h;
      } else if (b.classId == 1 && nCx == null) {
        nCx = b.cx; nCy = b.cy; nW = b.w; nH = b.h;
      } else if (b.classId == 2 && sCx == null) {
        sCx = b.cx; sCy = b.cy; sW = b.w; sH = b.h;
      }
    }

    return YoloDetection(
      syringeCx: sCx, syringeCy: sCy, syringeW: sW, syringeH: sH,
      armCx: aCx, armCy: aCy, armW: aW, armH: aH,
      needleCx: nCx, needleCy: nCy, needleW: nW, needleH: nH,
      imageWidth: _inputSize,
      imageHeight: _inputSize,
    );
  }

  static List<_BBox> _applyNms(List<_BBox> boxes) {
    List<_BBox> result = [];
    // Sort descending by probability
    boxes.sort((a, b) => b.prob.compareTo(a.prob));
    
    while (boxes.isNotEmpty) {
      final best = boxes.removeAt(0);
      result.add(best);
      boxes.removeWhere((b) => b.classId == best.classId && _iou(best, b) > _iouThreshold);
    }
    return result;
  }

  static double _iou(_BBox b1, _BBox b2) {
    final left = math.max(b1.cx - b1.w / 2, b2.cx - b2.w / 2);
    final top = math.max(b1.cy - b1.h / 2, b2.cy - b2.h / 2);
    final right = math.min(b1.cx + b1.w / 2, b2.cx + b2.w / 2);
    final bottom = math.min(b1.cy + b1.h / 2, b2.cy + b2.h / 2);

    if (left < right && top < bottom) {
      final intersection = (right - left) * (bottom - top);
      final area1 = b1.w * b1.h;
      final area2 = b2.w * b2.h;
      return intersection / (area1 + area2 - intersection);
    }
    return 0.0;
  }

  static double _computeAngle(YoloDetection d) {
    double armDx, armDy;
    if ((d.armW ?? 0) > (d.armH ?? 0)) {
      armDx = 1; armDy = 0;
    } else {
      armDx = 0; armDy = 1;
    }

    double syringeDx, syringeDy;
    if (d.hasNeedle) {
      syringeDx = d.needleCx! - d.syringeCx!;
      syringeDy = d.needleCy! - d.syringeCy!;
    } else {
      syringeDx = d.armCx! - d.syringeCx!;
      syringeDy = d.armCy! - d.syringeCy!;
    }

    final mag = math.sqrt(syringeDx * syringeDx + syringeDy * syringeDy);
    if (mag < 1e-6) return 0;
    syringeDx /= mag;
    syringeDy /= mag;

    final dot = (syringeDx * armDx + syringeDy * armDy).abs();
    final cosTheta = dot.clamp(0.0, 1.0);
    final angleRad = math.acos(cosTheta);
    return angleRad * 180.0 / math.pi;
  }

  static int scoreIMAngle(double measuredAngle) {
    final delta = (measuredAngle - 90.0).abs();
    if (delta <= 0.5) return 5; // Near perfect 90.0 degrees
    if (delta <= 5) return 4;
    if (delta <= 10) return 3; // 80-100 degrees passes
    if (delta <= 15) return 2;
    return 1;
  }
}
