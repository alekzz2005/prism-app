import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:provider/provider.dart';
import '../../providers/session_state_provider.dart';
import '../../widgets/angle_overlay_painter.dart';
import '../../widgets/angle_badge.dart';
import 'session_complete_screen.dart';

// ──────────────────────────────────────────────────────────
// Detection phase enum
// ──────────────────────────────────────────────────────────
enum DetectionPhase { insertion, aspiration, withdrawal }

// ──────────────────────────────────────────────────────────
// TODO: replace mock landmarks with MediaPipe when bindings available
// ──────────────────────────────────────────────────────────

/// UC-1.1 + 1.2 + 1.3 — 3-phase detection screen.
class DetectionScreen extends StatefulWidget {
  final String injectionType;
  const DetectionScreen({super.key, required this.injectionType});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  // ── Camera ──
  CameraController? _camera;
  bool _cameraReady = false;

  // ── Pose detector ──
  final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );
  bool _processing = false;

  // ── Mock landmark state ──
  // TODO: replace mock landmarks with MediaPipe when bindings available
  final _rng = math.Random();
  double _mockWristX = 200, _mockWristY = 400;
  double _mockIndexX = 280, _mockIndexY = 300;
  double _mockThumbX = 190, _mockThumbY = 380;
  List<Pose> _poses = [];
  Size _imageSize = const Size(480, 640);
  Timer? _mockTimer;

  // ── Phase ──
  DetectionPhase _phase = DetectionPhase.insertion;

  // ── Insertion ──
  double _liveAngle = 0;
  bool _angleInRange = false;
  double? _lockedInsertionAngle;

  // ── Aspiration ──
  bool _aspirationStarted = false;
  DateTime? _aspirationStart;
  double _aspirationElapsed = 0;
  double _aspirationInitialThumbY = 0;
  double _aspirationDisplacement = 0;
  Timer? _aspirationTimer;
  List<double> _thumbYHistory = [];
  static const _aspirationMinDuration = 5.0; // seconds
  static const _aspirationDisplacementThreshold = 10.0; // px

  // ── Withdrawal ──
  double? _lockedWithdrawalAngle;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _startMockLandmarks();
  }

  // ──────────────────────────────────────────────────────────
  // Camera init
  // ──────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _camera = CameraController(
        cam, ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await _camera!.initialize();
      await _camera!.startImageStream(_onFrame);
      if (mounted) setState(() => _cameraReady = true);
    } catch (_) {
      // Camera may fail on emulator — mock still runs
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  // ──────────────────────────────────────────────────────────
  // TODO: replace mock landmarks with MediaPipe when bindings available
  // Mock landmark ticker — slightly randomizes positions each frame
  // ──────────────────────────────────────────────────────────
  void _startMockLandmarks() {
    _mockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _mockWristX += _rng.nextDouble() * 4 - 2;
        _mockWristY += _rng.nextDouble() * 4 - 2;
        _mockIndexX += _rng.nextDouble() * 4 - 2;
        _mockIndexY += _rng.nextDouble() * 4 - 2;
        _mockThumbX += _rng.nextDouble() * 3 - 1.5;
        _mockThumbY += _rng.nextDouble() * 3 - 1.5;

        _liveAngle = _computeMockAngle();
        _updateAngleState();

        if (_aspirationStarted) {
          _aspirationDisplacement =
              (_mockThumbY - _aspirationInitialThumbY).abs();
          _thumbYHistory.add(_mockThumbY);
        }
      });
    });
  }

  double _computeMockAngle() {
    final dx = _mockIndexX - _mockWristX;
    final dy = _mockWristY - _mockIndexY; // invert Y (screen coords)
    return (math.atan2(dy, dx.abs()) * 180 / math.pi).clamp(0.0, 90.0);
  }

  void _updateAngleState() {
    final config = context.read<SessionStateProvider>().currentConfig;
    if (config == null) return;
    final delta = (_liveAngle - config.targetAngle).abs();
    _angleInRange = delta <= config.tolerance;
  }

  // ──────────────────────────────────────────────────────────
  // Real camera frame processing (when camera works)
  // ──────────────────────────────────────────────────────────
  void _onFrame(CameraImage image) async {
    if (_processing) return;
    _processing = true;
    try {
      final cam = _camera?.description;
      if (cam == null) return;
      final rotation =
          InputImageRotationValue.fromRawValue(cam.sensorOrientation);
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (rotation == null || format == null) return;

      final inputImage = InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final detected = await _detector.processImage(inputImage);
      if (detected.isNotEmpty && mounted) {
        setState(() {
          _poses = detected;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });
      }
    } finally {
      _processing = false;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Scoring helpers
  // ──────────────────────────────────────────────────────────
  int _scoreAngle(double measured, double target) {
    final delta = (measured - target).abs();
    if (delta <= 1) return 5;
    if (delta <= 2) return 4;
    if (delta <= 3) return 3;
    if (delta <= 5) return 2;
    return 1;
  }

  // ──────────────────────────────────────────────────────────
  // Phase actions
  // ──────────────────────────────────────────────────────────
  void _lockInsertion() {
    final session = context.read<SessionStateProvider>();
    final config = session.currentConfig!;
    final score = _scoreAngle(_liveAngle, config.targetAngle);
    session.setInsertion(_liveAngle, score);
    setState(() {
      _lockedInsertionAngle = _liveAngle;
      _phase = DetectionPhase.aspiration;
    });
  }

  void _startAspiration() {
    setState(() {
      _aspirationStarted = true;
      _aspirationStart = DateTime.now();
      _aspirationInitialThumbY = _mockThumbY;
      _thumbYHistory = [_mockThumbY];
    });

    _aspirationTimer =
        Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        _aspirationElapsed = DateTime.now()
            .difference(_aspirationStart!)
            .inMilliseconds /
            1000.0;
      });
    });
  }

  void _lockAspiration() {
    _aspirationTimer?.cancel();
    final session = context.read<SessionStateProvider>();

    String result;
    if (_aspirationDisplacement > _aspirationDisplacementThreshold &&
        _aspirationElapsed >= _aspirationMinDuration) {
      result = 'Correct';
    } else if (_aspirationDisplacement > _aspirationDisplacementThreshold) {
      result = 'Incorrect';
    } else {
      result = 'Not Detected';
      session.setFlagged(true);
    }

    final smoothness = _computeSmoothness();

    session.setAspiration(
      result: result,
      duration: _aspirationElapsed,
      smoothness: smoothness,
    );

    setState(() => _phase = DetectionPhase.withdrawal);
  }

  String _computeSmoothness() {
    if (_thumbYHistory.length < 3) return 'Good';
    double totalJitter = 0;
    for (int i = 1; i < _thumbYHistory.length; i++) {
      totalJitter += (_thumbYHistory[i] - _thumbYHistory[i - 1]).abs();
    }
    return (totalJitter / (_thumbYHistory.length - 1)) < 5.0 ? 'Good' : 'Low';
  }

  void _lockWithdrawal() {
    final session = context.read<SessionStateProvider>();
    final config = session.currentConfig!;
    final score = _scoreAngle(_liveAngle, config.targetAngle);
    final delta = (_liveAngle - (_lockedInsertionAngle ?? 0)).abs();
    final correspondence = delta <= 5.0 ? 'Matches' : 'Deviates';

    session.setWithdrawal(_liveAngle, score);
    session.setCorrespondence(correspondence, delta);

    // Aspiration score: Correct=5, Incorrect=2, Not Detected=1
    final aspScore = session.aspirationResult == 'Correct'
        ? 5
        : session.aspirationResult == 'Incorrect'
            ? 2
            : 1;

    final overall = ((session.insertionScore! + session.withdrawalScore! + aspScore) / 3).round();
    session.setOverallScore(overall);

    setState(() => _lockedWithdrawalAngle = _liveAngle);
  }

  void _completeSession() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SessionCompleteScreen()),
    );
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    _aspirationTimer?.cancel();
    _camera?.stopImageStream();
    _camera?.dispose();
    _detector.close();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStateProvider>();
    final config = session.currentConfig;
    final target = config?.targetAngle ?? 0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: _PhaseIndicator(phase: _phase),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ── Camera + overlay ──
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Camera or dark background
                _cameraReady
                    ? CameraPreview(_camera!)
                    : Container(color: const Color(0xFF111122)),

                // Skeleton overlay (real or mock)
                if (_poses.isNotEmpty)
                  CustomPaint(
                    painter: AngleOverlayPainter(
                      poses: _poses,
                      imageSize: _imageSize,
                    ),
                  )
                else
                  // TODO: replace mock landmarks with MediaPipe when bindings available
                  CustomPaint(
                    painter: _MockOverlayPainter(
                      wrist: Offset(_mockWristX, _mockWristY),
                      index: Offset(_mockIndexX, _mockIndexY),
                      thumb: Offset(_mockThumbX, _mockThumbY),
                    ),
                  ),

                // Live angle badge (phase 1 & 3)
                if (_phase != DetectionPhase.aspiration)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: AngleBadge(
                      angle: '${_liveAngle.toStringAsFixed(1)}°',
                      color: _angleInRange
                          ? Colors.green.shade700
                          : Colors.deepPurple.shade700,
                    ),
                  ),

                // Target badge
                if (_phase != DetectionPhase.aspiration)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: AngleBadge(
                      angle: 'Target: ${target.toStringAsFixed(0)}°',
                      color: Colors.blueGrey.shade700,
                    ),
                  ),

                // Aspiration timer
                if (_phase == DetectionPhase.aspiration && _aspirationStarted)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: AngleBadge(
                      angle:
                          '${_aspirationElapsed.toStringAsFixed(1)}s  •  ${_aspirationDisplacement.toStringAsFixed(0)}px',
                      color: Colors.teal.shade700,
                    ),
                  ),
              ],
            ),
          ),

          // ── Control bar ──
          _buildControlBar(session),
        ],
      ),
    );
  }

  Widget _buildControlBar(SessionStateProvider session) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      color: const Color(0xFF1A1A2E),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Phase-specific metrics row
          _buildMetrics(session),
          const SizedBox(height: 14),

          // Phase-specific action button
          if (_phase == DetectionPhase.insertion)
            _ActionButton(
              key: const Key('lock_insertion_button'),
              label: 'Lock Insertion Angle',
              enabled: _angleInRange,
              color: Colors.deepPurpleAccent,
              onPressed: _lockInsertion,
            ),

          if (_phase == DetectionPhase.aspiration) ...[
            if (!_aspirationStarted)
              _ActionButton(
                key: const Key('start_aspiration_button'),
                label: 'Start Aspiration',
                enabled: true,
                color: Colors.teal,
                onPressed: _startAspiration,
              )
            else
              _ActionButton(
                key: const Key('lock_aspiration_button'),
                label: 'Done Aspirating  (${_aspirationElapsed.toStringAsFixed(1)}s)',
                enabled: _aspirationElapsed >= 1.0,
                color: Colors.teal,
                onPressed: _lockAspiration,
              ),
          ],

          if (_phase == DetectionPhase.withdrawal) ...[
            if (_lockedWithdrawalAngle == null)
              _ActionButton(
                key: const Key('lock_withdrawal_button'),
                label: 'Lock Withdrawal Angle',
                enabled: _angleInRange,
                color: Colors.indigo,
                onPressed: _lockWithdrawal,
              )
            else
              _ActionButton(
                key: const Key('complete_session_button'),
                label: 'Complete Session',
                enabled: true,
                color: Colors.green,
                onPressed: _completeSession,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetrics(SessionStateProvider session) {
    if (_phase == DetectionPhase.insertion) {
      return _MetricsRow(items: {
        'Live': '${_liveAngle.toStringAsFixed(1)}°',
        'Target': '${(session.currentConfig?.targetAngle ?? 0).toStringAsFixed(0)}°',
        'In range': _angleInRange ? '✓' : '✗',
      });
    }
    if (_phase == DetectionPhase.aspiration) {
      return _MetricsRow(items: {
        'Insertion': '${_lockedInsertionAngle?.toStringAsFixed(1) ?? '—'}°',
        'Score': '${session.insertionScore ?? '—'}/5',
        'Displacement': '${_aspirationDisplacement.toStringAsFixed(0)}px',
      });
    }
    // withdrawal
    return _MetricsRow(items: {
      'Live': '${_liveAngle.toStringAsFixed(1)}°',
      'Insertion': '${_lockedInsertionAngle?.toStringAsFixed(1) ?? '—'}°',
      'Delta': _lockedWithdrawalAngle != null
          ? '${(_liveAngle - (_lockedInsertionAngle ?? 0)).abs().toStringAsFixed(1)}°'
          : '—',
    });
  }
}

// ──────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────

class _PhaseIndicator extends StatelessWidget {
  final DetectionPhase phase;
  const _PhaseIndicator({required this.phase});

  @override
  Widget build(BuildContext context) {
    const phases = ['INSERTION', 'ASPIRATION', 'WITHDRAWAL'];
    final idx = phase.index;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(phases.length, (i) {
        final active = i == idx;
        final done = i < idx;
        return Row(
          children: [
            if (i > 0)
              Container(
                  width: 20,
                  height: 1.5,
                  color: done ? Colors.deepPurpleAccent : Colors.white24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: active
                    ? Colors.deepPurpleAccent
                    : done
                        ? Colors.deepPurple.shade900
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active || done
                      ? Colors.deepPurpleAccent
                      : Colors.white24,
                ),
              ),
              child: Text(
                phases[i],
                style: TextStyle(
                  color: active
                      ? Colors.white
                      : done
                          ? Colors.deepPurpleAccent
                          : Colors.white38,
                  fontSize: 10,
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      );
}

class _MetricsRow extends StatelessWidget {
  final Map<String, String> items;
  const _MetricsRow({required this.items});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.entries
            .map((e) => Column(
                  children: [
                    Text(e.key,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(e.value,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ))
            .toList(),
      );
}

// ──────────────────────────────────────────────────────────
// TODO: replace mock landmarks with MediaPipe when bindings available
// Draws a simple wrist→index line and a thumb dot
// ──────────────────────────────────────────────────────────
class _MockOverlayPainter extends CustomPainter {
  final Offset wrist;
  final Offset index;
  final Offset thumb;

  const _MockOverlayPainter({
    required this.wrist,
    required this.index,
    required this.thumb,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.8)
      ..strokeWidth = 3;
    final dotPaint = Paint()..color = Colors.greenAccent;
    final thumbPaint = Paint()..color = Colors.amberAccent;

    canvas.drawLine(wrist, index, linePaint);
    canvas.drawCircle(wrist, 6, dotPaint);
    canvas.drawCircle(index, 5, dotPaint);
    canvas.drawCircle(thumb, 5, thumbPaint);
  }

  @override
  bool shouldRepaint(_MockOverlayPainter old) => true;
}
