import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// CustomPainter that draws the L0→L8 skeleton overlay on top of the camera preview.
class AngleOverlayPainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;

  AngleOverlayPainter({required this.poses, required this.imageSize});

  static const _connections = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex],
    [PoseLandmarkType.leftWrist, PoseLandmarkType.leftThumb],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex],
    [PoseLandmarkType.rightWrist, PoseLandmarkType.rightThumb],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 6
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.75)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (final pose in poses) {
      for (final conn in _connections) {
        final p1 = pose.landmarks[conn[0]];
        final p2 = pose.landmarks[conn[1]];
        if (p1 != null && p2 != null) {
          canvas.drawLine(_scale(p1, size), _scale(p2, size), linePaint);
        }
      }
      for (final lm in pose.landmarks.values) {
        canvas.drawCircle(_scale(lm, size), 4, pointPaint);
      }
    }
  }

  Offset _scale(PoseLandmark lm, Size canvas) => Offset(
        lm.x * canvas.width / imageSize.width,
        lm.y * canvas.height / imageSize.height,
      );

  @override
  bool shouldRepaint(AngleOverlayPainter old) =>
      old.poses != poses || old.imageSize != imageSize;
}
