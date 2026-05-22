import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:provider/provider.dart';

import '../../providers/user_role_provider.dart';
import '../../services/hand_landmark_service.dart';
import '../../services/detection_service.dart';
import '../../services/aspiration_detection_service.dart';
import '../../services/live_session_service.dart';
import '../../widgets/angle_overlay_painter.dart';

class CameraNodeScreen extends StatefulWidget {
  const CameraNodeScreen({super.key});

  @override
  State<CameraNodeScreen> createState() => _CameraNodeScreenState();
}

class _CameraNodeScreenState extends State<CameraNodeScreen> {
  CameraController? _camera;
  bool _cameraReady = false;
  int _sensorOrientation = 90;

  final HandLandmarkService _landmarkService = HandLandmarkService();
  bool _processing = false;
  List<Hand> _hands = [];

  final LiveSessionService _liveService = LiveSessionService();
  final AspirationDetectionService _aspirationService = AspirationDetectionService();

  double _liveAngle = 0;
  String _currentPhase = 'waiting';

  Timer? _syncTimer;
  double? _lastInsertionAngle;

  @override
  void initState() {
    super.initState();
    _landmarkService.init();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      _camera = CameraController(cam, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await _camera!.initialize();
      await _camera!.startImageStream(_onFrame);
      if (mounted) setState(() => _cameraReady = true);

      // Start 2Hz sync timer
      _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _syncLiveAngle());
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  void _syncLiveAngle() {
    if (!mounted) return;
    if (_currentPhase != 'insertion' && _currentPhase != 'withdrawal') return;
    if (_liveAngle < 0) return;

    final instructorId = context.read<UserRoleProvider>().uid;
    if (instructorId != null) {
      _liveService.updateLiveAngle(instructorId, _liveAngle);
    }
  }

  void _onFrame(CameraImage image) {
    if (_processing) return;
    _processing = true;
    try {
      final cam = _camera?.description;
      if (cam == null) return;
      
      final detected = _landmarkService.detect(image, cam.sensorOrientation);
      if (mounted) {
        setState(() {
          _hands = detected;
          _sensorOrientation = cam.sensorOrientation;
          
          if (_hands.isNotEmpty) {
            final angle = AngleComputationUtil.computeDartGripAngle(_hands, sensorOrientation: _sensorOrientation);
            if (angle >= 0) _liveAngle = angle;

            if (_currentPhase == 'aspiration') {
              _aspirationService.update(_hands, sensorOrientation: _sensorOrientation);
            }
          }
        });
      }
    } finally {
      _processing = false;
    }
  }

  int _scoreAngle(double measured, double target) {
    final delta = (measured - target).abs();
    if (delta <= 1) return 5;
    if (delta <= 2) return 4;
    if (delta <= 3) return 3;
    if (delta <= 5) return 2;
    return 1;
  }

  void _handlePhaseChange(String instructorId, LiveSessionModel session, String oldPhase) {
    if (session.phase == oldPhase) return;
    _currentPhase = session.phase;

    if (session.phase == 'insertion_locked' && oldPhase == 'insertion') {
      final score = _scoreAngle(_liveAngle, session.targetAngle);
      _lastInsertionAngle = _liveAngle;
      _liveService.saveInsertionMetrics(instructorId, _liveAngle, score);
    } else if (session.phase == 'aspiration' && oldPhase == 'insertion_locked') {
      _aspirationService.reset();
      AngleComputationUtil.resetSmoothing();
    } else if (session.phase == 'aspiration_locked' && oldPhase == 'aspiration') {
      _liveService.saveAspirationMetrics(instructorId, _aspirationService.result, _aspirationService.duration, _aspirationService.smoothness);
    } else if (session.phase == 'withdrawal' && oldPhase == 'aspiration_locked') {
      AngleComputationUtil.resetSmoothing();
    } else if (session.phase == 'withdrawal_locked' && oldPhase == 'withdrawal') {
      final score = _scoreAngle(_liveAngle, session.targetAngle);
      final delta = (_liveAngle - (_lastInsertionAngle ?? 0)).abs();
      final corr = delta <= 5.0 ? 'Matches' : 'Deviates';
      _liveService.saveWithdrawalMetrics(instructorId, _liveAngle, score, corr, delta);
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _camera?.stopImageStream();
    _camera?.dispose();
    _landmarkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instructorId = context.watch<UserRoleProvider>().uid;

    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<LiveSessionModel?>(
        stream: _liveService.watchSession(instructorId!),
        builder: (context, snapshot) {
          final session = snapshot.data;

          if (session != null && session.phase != _currentPhase) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handlePhaseChange(instructorId, session, _currentPhase);
            });
          }

          if (session == null || session.phase == 'waiting') {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cast_connected, color: Colors.deepPurpleAccent, size: 64),
                  const SizedBox(height: 16),
                  const Text('CAMERA NODE ACTIVE', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  const Text('Place on tripod and wait for remote start...', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Exit Camera Mode'),
                  )
                ],
              ),
            );
          }

          // Active detection view (minimal, for instructor visibility only)
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_cameraReady) CameraPreview(_camera!),
              if (_hands.isNotEmpty) CustomPaint(painter: AngleOverlayPainter(hands: _hands, sensorOrientation: _sensorOrientation)),
              
              // Top Status Banner
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${session.studentName} — ${session.injectionType}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('Phase: ${session.phase.toUpperCase()}', style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 12)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () {
                          _liveService.clearSession(instructorId);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
