import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'roboflow_service.dart'; // To reuse AngleResult and RoboflowDetection

/// Represents a single detected bounding box from YOLO.
class BBox {
  final double x;
  final double y;
  final double w;
  final double h;
  final double confidence;

  BBox(this.x, this.y, this.w, this.h, this.confidence);
}

/// Data sent to the Isolate for TFLite inference.
class TfliteFrameData {
  final int width;
  final int height;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uRowStride;
  final int uvPixelStride;
  final int sensorOrientation;
  final bool isIOS;

  TfliteFrameData({
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

class TfliteDetectionService {
  static const int inputSize = 640;
  static const double confidenceThreshold = 0.15;
  static const double iouThreshold = 0.45;

  /// Holds the model paths
  static const String _armModelPath = 'assets/models/arms/arms.tflite';
  static const String _syringeModelPath = 'assets/models/syringe/syringe.tflite';

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

  static Interpreter? _armInterpreter;
  static Interpreter? _syringeInterpreter;
  
  static IsolateInterpreter? _armIsolateInterpreter;
  static IsolateInterpreter? _syringeIsolateInterpreter;
  
  static bool _isProcessing = false;

  /// Call this once before starting detection
  static Future<void> init() async {
    if (_armInterpreter != null) return;
    try {
      final options = InterpreterOptions()..threads = 4;
      _armInterpreter = await Interpreter.fromAsset(_armModelPath, options: options);
      _syringeInterpreter = await Interpreter.fromAsset(_syringeModelPath, options: options);
      
      _armIsolateInterpreter = await IsolateInterpreter.create(address: _armInterpreter!.address);
      _syringeIsolateInterpreter = await IsolateInterpreter.create(address: _syringeInterpreter!.address);
      
      debugPrint('[TfliteService] Models and Isolates loaded successfully!');
    } catch (e) {
      debugPrint('[TfliteService] Failed to load models: $e');
    }
  }

  /// Calculates the relative injection angle (mirrors RoboflowDetectionService).
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

    final mag = math.sqrt(syringeDx * syringeDx + syringeDy * syringeDy);
    if (mag < 1e-6) return 0;
    syringeDx /= mag;
    syringeDy /= mag;

    final dot = (syringeDx * armDx + syringeDy * armDy).abs();
    final cosTheta = dot.clamp(0.0, 1.0);
    final angleRad = math.acos(cosTheta);
    final angleDeg = angleRad * 180.0 / math.pi;

    return angleDeg;
  }

  static int scoreIMAngle(double measuredAngle) {
    final delta = (measuredAngle - 90.0).abs();
    if (delta <= 0.5) return 5; // Near perfect 90.0 degrees
    if (delta <= 5) return 4;
    if (delta <= 10) return 3; // 80-100 degrees passes
    if (delta <= 15) return 2;
    return 1;
  }

  /// Called directly from the UI by CameraNodeScreen.
  /// Accepts pre-extracted frame data so the CameraImage can be GC'd immediately.
  static Future<AngleResult?> detectAngleFromFrameData(TfliteFrameData frameData) async {
    if (_armIsolateInterpreter == null || _syringeIsolateInterpreter == null) {
      debugPrint('[TfliteService] Interpreters not initialized!');
      return AngleResult.lost;
    }
    
    if (_isProcessing) return null; // Skip frame if already crunching AI math

    _isProcessing = true;
    try {
      // 1. Preprocess image inline (fast for 320x240, no isolate overhead)
      final Float32List? inputBuffer = _preprocessImage(frameData);
      
      if (inputBuffer == null) return AngleResult.lost;

      // 2. Run Inference completely in background using IsolateInterpreter
      var armOutput = List.generate(1, (i) => List.generate(6, (j) => List.filled(8400, 0.0)));
      var syringeOutput = List.generate(1, (i) => List.generate(6, (j) => List.filled(8400, 0.0)));

      // Run both concurrently in the background so the UI doesn't freeze
      await Future.wait([
        _armIsolateInterpreter!.run(inputBuffer.reshape([1, inputSize, inputSize, 3]), armOutput),
        _syringeIsolateInterpreter!.run(inputBuffer.reshape([1, inputSize, inputSize, 3]), syringeOutput),
      ]);

      // 3. Parse Outputs
      final armDetections = _parseYoloOutput(armOutput[0], numClasses: 2, modelName: 'Arm Model');
      final syringeDetections = _parseYoloOutput(syringeOutput[0], numClasses: 2, modelName: 'Syringe Model');

      BBox? armBox = armDetections[0] ?? armDetections[1]; 
      BBox? syringeBox = syringeDetections[0];
      BBox? needleBox = syringeDetections[1];

      if (armBox == null && syringeBox == null) {
         return AngleResult.lost;
      }
      
      // Map back to original aspect ratio
      bool isRotated = frameData.sensorOrientation == 90 || frameData.sensorOrientation == 270;
      double origW = isRotated ? frameData.height.toDouble() : frameData.width.toDouble();
      double origH = isRotated ? frameData.width.toDouble() : frameData.height.toDouble();
      
      // YOLOv8 TFLite outputs normalized coordinates (0.0 - 1.0).
      // Since we stretched the image using copyResize(640x640), the normalized coords 
      // map directly to the original aspect ratio by just multiplying by origW / origH.
      double scaleX = origW;
      double scaleY = origH;

      final detection = RoboflowDetection(
        armCx: armBox != null ? armBox.x * scaleX : null,
        armCy: armBox != null ? armBox.y * scaleY : null,
        armW:  armBox != null ? armBox.w * scaleX : null,
        armH:  armBox != null ? armBox.h * scaleY : null,
        
        syringeCx: syringeBox != null ? syringeBox.x * scaleX : null,
        syringeCy: syringeBox != null ? syringeBox.y * scaleY : null,
        syringeW:  syringeBox != null ? syringeBox.w * scaleX : null,
        syringeH:  syringeBox != null ? syringeBox.h * scaleY : null,
        
        needleCx: needleBox != null ? needleBox.x * scaleX : null,
        needleCy: needleBox != null ? needleBox.y * scaleY : null,
        needleW:  needleBox != null ? needleBox.w * scaleX : null,
        needleH:  needleBox != null ? needleBox.h * scaleY : null,
        
        imageWidth: origW.toInt(),
        imageHeight: origH.toInt(),
      );

      bool detectionLost = !detection.hasSyringe || !detection.hasArm;
      double smoothedAngle = -1;
      int score = 0;

      debugPrint('[TfliteService] Parsed boxes - Arm: ${armBox?.x}, ${armBox?.y}, ${armBox?.w}, ${armBox?.h} | Syringe: ${syringeBox?.x}, ${syringeBox?.y}, ${syringeBox?.w}, ${syringeBox?.h}');
      debugPrint('[TfliteService] Canvas coords - Arm: ${detection.armCx}, ${detection.armCy}, ${detection.armW}, ${detection.armH} | Syringe: ${detection.syringeCx}, ${detection.syringeCy}, ${detection.syringeW}, ${detection.syringeH}');

      if (!detectionLost) {
        final rawAngle = _computeAngle(detection);
        smoothedAngle = _smooth(rawAngle);
        score = scoreIMAngle(smoothedAngle);
      } else {
        resetSmoothing();
      }

      return AngleResult(
          angle: smoothedAngle,
          score: score,
          detectionLost: detectionLost, // True if we can't compute an angle, but we still return the partial detection
          detection: detection);
    } catch (e, st) {
      debugPrint('[TfliteService] Error: $e\n$st');
      return AngleResult.lost;
    } finally {
      _isProcessing = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  IMAGE PREPROCESSING (inline, fast for low-res frames)
  // ═══════════════════════════════════════════════════════════════════════════

  static Float32List? _preprocessImage(TfliteFrameData frame) {
    try {
      // 1. Reconstruct YUV to RGB Image
      final image = img.Image(width: frame.width, height: frame.height);
      for (int y = 0; y < frame.height; y++) {
        for (int x = 0; x < frame.width; x++) {
          final int yIndex = y * frame.yRowStride + x;
          final int uvIndex =
              (y ~/ 2) * frame.uRowStride + (x ~/ 2) * frame.uvPixelStride;

          if (yIndex >= frame.yBytes.length || uvIndex >= frame.uBytes.length)
            continue;

          final int vIndex = frame.isIOS ? uvIndex + 1 : uvIndex;
          if (vIndex >= frame.vBytes.length) continue;

          final int yVal = frame.yBytes[yIndex];
          final int uVal = frame.uBytes[uvIndex] - 128;
          final int vVal = frame.vBytes[vIndex] - 128;

          int r = (yVal + 1.402 * vVal).round().clamp(0, 255);
          int g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
          int b = (yVal + 1.772 * uVal).round().clamp(0, 255);

          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      img.Image uprightImage = image;
      if (frame.sensorOrientation == 90) {
        uprightImage = img.copyRotate(image, angle: 90);
      } else if (frame.sensorOrientation == 270) {
        uprightImage = img.copyRotate(image, angle: 270);
      } else if (frame.sensorOrientation == 180) {
        uprightImage = img.copyRotate(image, angle: 180);
      }

      // 2. Preprocess to Float32 Tensor [1, 640, 640, 3]
      final resized = img.copyResize(uprightImage, width: inputSize, height: inputSize);
      
      var inputBuffer = Float32List(1 * inputSize * inputSize * 3);
      int pixelIndex = 0;
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          inputBuffer[pixelIndex++] = pixel.r / 255.0;
          inputBuffer[pixelIndex++] = pixel.g / 255.0;
          inputBuffer[pixelIndex++] = pixel.b / 255.0;
        }
      }

      return inputBuffer;
    } catch (e) {
      debugPrint('[TfliteIsolate] Error: $e');
      return null;
    }
  }

  /// Parses a YOLO tensor [numClasses + 4, 8400] and returns the highest confidence bounding box for each class.
  static Map<int, BBox> _parseYoloOutput(List<List<double>> output, {required int numClasses, required String modelName}) {
    Map<int, BBox> bestBoxes = {};
    Map<int, double> bestConfidences = {};
    
    // To debug what the AI is actually seeing (even if below threshold)
    Map<int, double> absoluteMaxConf = {};

    int numAnchors = output[0].length;
    for (int i = 0; i < numAnchors; i++) {
      for (int c = 0; c < numClasses; c++) {
        double confidence = output[4 + c][i];
        
        if (!absoluteMaxConf.containsKey(c) || confidence > absoluteMaxConf[c]!) {
            absoluteMaxConf[c] = confidence;
        }

        if (confidence > confidenceThreshold) {
          if (!bestConfidences.containsKey(c) || confidence > bestConfidences[c]!) {
            bestConfidences[c] = confidence;
            bestBoxes[c] = BBox(
              output[0][i], // X
              output[1][i], // Y
              output[2][i], // W
              output[3][i], // H
              confidence,
            );
          }
        }
      }
    }
    
    print('[$modelName] Max confidence seen -> Class 0: ${(absoluteMaxConf[0] ?? 0).toStringAsFixed(3)}, Class 1: ${(absoluteMaxConf[1] ?? 0).toStringAsFixed(3)}');

    return bestBoxes;
  }
}
