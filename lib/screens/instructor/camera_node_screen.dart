import 'dart:async';

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/user_role_provider.dart';
<<<<<<< HEAD
import '../../services/hand_landmark_service.dart';
import '../../services/detection_service.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../services/pose_landmark_service.dart';
import '../../services/live_session_service.dart';
import '../../widgets/angle_overlay_painter.dart';
=======
import '../../services/roboflow_service.dart';
import '../../services/live_session_service.dart';
import '../../widgets/detection_overlay_painter.dart';
>>>>>>> 74ac01c059d91ae140119d83ade8f5ca3d44124e

// ─── Brand Colours ─────────────────────────────────────────────────────────
const _accentBlue = Color(0xFFA8C4E0);
const _green      = Color(0xFF4ADE80);
const _greenDark  = Color(0xFF22C55E);
// ──────────────────────────────────────────────────────────────────────────────

class CameraNodeScreen extends StatefulWidget {
  const CameraNodeScreen({super.key});

  @override
  State<CameraNodeScreen> createState() => _CameraNodeScreenState();
}

class _CameraNodeScreenState extends State<CameraNodeScreen> {
  CameraController? _camera;
  bool _cameraReady = false;
  int _sensorOrientation = 90;

  bool _processing = false;
  final LiveSessionService _liveService = LiveSessionService();

  double _liveAngle = 0;
  String _currentPhase = 'waiting';
  Size? _imageSize;
  LiveSessionModel? _currentSession;

  Timer? _syncTimer;
  double? _lastInsertionAngle;
  String? _instructorId;

  // Roboflow detection state
  bool _detectionLost = false;
  RoboflowDetection? _latestDetection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _instructorId = context.read<UserRoleProvider>().uid;
      
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        _initCamera();
      });
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _camera?.stopImageStream();
    _camera?.dispose();
    if (_instructorId != null) {
      _liveService.setCameraActive(_instructorId!, false);
    }
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _camera = CameraController(cam, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await _camera!.initialize();
      // Roboflow API — no local model loading needed
      await _camera!.startImageStream(_onFrame);
      if (mounted) setState(() => _cameraReady = true);
      
      if (_instructorId != null) {
        _liveService.setCameraActive(_instructorId!, true);
      }
      
      // 2Hz sync timer removed. We process frames directly using throttling in _onFrame.
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  // ─── 2Hz Sync ─────────────────────────────────────────────────────────────
  Future<void> _syncMetrics(RoboflowFrameData frameData) async {
    if (!mounted) return;
    
    final instructorId = _instructorId;
    if (instructorId == null) {
      debugPrint('[CameraNode] ❌ No instructorId, skipping');
      return;
    }

    if (_currentPhase == 'waiting' || _currentPhase == 'completed') {
      debugPrint('[CameraNode] ⏸ Phase=$_currentPhase, skipping frame');
      return;
    }

    debugPrint('[CameraNode] 📸 Sending frame to Roboflow API (phase=$_currentPhase, ${frameData.width}x${frameData.height})');

    // Send to Roboflow API and get angle result
    final result = await RoboflowDetectionService.detectAngleFromFrameData(frameData);
    
    debugPrint('[CameraNode] 📊 Result: lost=${result.detectionLost}, angle=${result.angle.toStringAsFixed(1)}, score=${result.score}, hasDetection=${result.detection != null}');
    if (result.detection != null) {
      final d = result.detection!;
      debugPrint('[CameraNode] 🎯 Arm=(${d.armCx?.toStringAsFixed(0)},${d.armCy?.toStringAsFixed(0)}) Syringe=(${d.syringeCx?.toStringAsFixed(0)},${d.syringeCy?.toStringAsFixed(0)}) Needle=(${d.needleCx?.toStringAsFixed(0)},${d.needleCy?.toStringAsFixed(0)})');
    }

    if (!mounted) return;

    setState(() {
      _detectionLost = result.detectionLost;
      _latestDetection = result.detection;
      if (!result.detectionLost) {
        _liveAngle = result.angle;
        _liveScore = result.score;
      }
    });

    _liveService.setDetectionLost(instructorId, result.detectionLost);

    if (result.detectionLost) return;

    if (_currentPhase == 'insertion' || _currentPhase == 'withdrawal') {
      if (_liveAngle >= 0) {
        _liveService.updateLiveAngle(instructorId, _liveAngle);
      }
    }
  }

  // ─── Frame Processing ────────────────────────────────────────────────────────
  
  int _lastProcessTime = 0;
  bool _isProcessingFrame = false;

  void _onFrame(CameraImage image) {
    if (_currentPhase == 'waiting' || _currentPhase == 'completed') return;
    
    // Always update aspect ratio
    if (mounted && _imageSize == null) {
      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    }

    // Throttle to 2 FPS (500ms) to allow GC to release CameraImage buffers
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProcessTime < 500) return;
    if (_isProcessingFrame) return;

    _isProcessingFrame = true;
    _lastProcessTime = now;

    // *** CRITICAL: Extract raw bytes SYNCHRONOUSLY right here ***
    // This ensures CameraImage native buffer is freed the instant _onFrame returns
    final isIOS = image.planes.length == 2;
    final frameData = RoboflowFrameData(
      width: image.width,
      height: image.height,
      yBytes: Uint8List.fromList(image.planes[0].bytes),
      uBytes: Uint8List.fromList(image.planes[1].bytes),
      vBytes: isIOS
          ? Uint8List.fromList(image.planes[1].bytes)
          : Uint8List.fromList(image.planes[2].bytes),
      yRowStride: image.planes[0].bytesPerRow,
      uRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? (isIOS ? 2 : 1),
      sensorOrientation: _camera?.description.sensorOrientation ?? 90,
      isIOS: isIOS,
    );

    debugPrint('[CameraNode] 🖼 _onFrame fired — phase=$_currentPhase, ${image.width}x${image.height}');

    // Now process the copied bytes asynchronously (CameraImage is NOT referenced)
    _processFrameWrapper(frameData);
  }

  Future<void> _processFrameWrapper(RoboflowFrameData frameData) async {
    try {
      await _syncMetrics(frameData);
    } finally {
      _isProcessingFrame = false;
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

    if (session.phase == 'waiting' || session.phase == 'completed') {
      setState(() {
        _lastInsertionAngle = null;
        _detectionLost = false;
      });
      AngleComputationUtil.resetSmoothing();
    } else if (session.phase == 'insertion_locked' && oldPhase == 'insertion') {
      final score = _scoreAngle(_liveAngle, session.targetAngle);
      _lastInsertionAngle = _liveAngle;
      _liveService.saveInsertionMetrics(instructorId, _liveAngle, score);
    } else if (session.phase == 'aspiration' && oldPhase == 'insertion_locked') {
      RoboflowDetectionService.resetSmoothing();
    } else if (session.phase == 'aspiration_locked' && oldPhase == 'aspiration') {
      AngleComputationUtil.resetSmoothing();
    } else if (session.phase == 'withdrawal' && oldPhase == 'aspiration_locked') {
      AngleComputationUtil.resetSmoothing();
    } else if (session.phase == 'withdrawal_locked' && oldPhase == 'withdrawal') {
      final score = _scoreAngle(_liveAngle, session.targetAngle);
      final delta = (_liveAngle - (_lastInsertionAngle ?? 0)).abs();
      final corr  = delta <= 5.0 ? 'Matches' : 'Deviates';
      _liveService.saveWithdrawalMetrics(instructorId, _liveAngle, score, corr, delta);
    }
  }

  String _formatName(String fullName) {
    final parts = fullName.split(',');
    if (parts.length == 1) return fullName;
    final last = parts[0].trim();
    final firstsWords = parts[1].trim().split(' ').where((w) => w.isNotEmpty).toList();
    if (firstsWords.isEmpty) return last;
    final firstInitial = '${firstsWords[0][0].toUpperCase()}.';
    return '$last, $firstInitial';
  }


  @override
  Widget build(BuildContext context) {
    final instructorId = context.watch<UserRoleProvider>().uid;
    _instructorId = instructorId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<LiveSessionModel?>(
        stream: _liveService.watchSession(instructorId!),
        builder: (context, snapshot) {
          final session = snapshot.data;
          _currentSession = session;

          if (session != null && !session.cameraNodeActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _liveService.setCameraActive(instructorId, true);
            });
          }

          if (session != null && session.phase != _currentPhase) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handlePhaseChange(instructorId, session, _currentPhase);
            });
          } else if (session == null && _currentPhase != 'waiting') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _currentPhase = 'waiting';
                  _lastInsertionAngle = null;
                });
                AngleComputationUtil.resetSmoothing();
              }
            });
          }

          final isWaiting = session == null || session.phase == 'waiting';

          return Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF001428), Color(0xFF001C38), Color(0xFF000E1E)],
                  ),
                ),
              ),
              if (!_cameraReady)
                Container(
                  color: const Color(0xFF003366),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        SizedBox(height: 24),
                        Text(
                          'PRISM',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 6),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'INITIALIZING CAMERA...',
                          style: TextStyle(color: Color(0xFFA8C4E0), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 2),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_cameraReady && _camera?.value.previewSize != null) 
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _camera!.value.previewSize!.height,
                      height: _camera!.value.previewSize!.width,
                      child: Stack(
                        children: [
                          CameraPreview(_camera!),
                          // ── Roboflow detection overlay ──
                          if (_latestDetection != null && !isWaiting)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: DetectionOverlayPainter(
                                  detection: _latestDetection,
                                  previewSize: Size(
                                    _camera!.value.previewSize!.height,
                                    _camera!.value.previewSize!.width,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (!isWaiting) ..._buildCornerGuides(),

              if (isWaiting)
                Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF003366).withValues(alpha: 0.35),
                            border: Border.all(color: _accentBlue.withValues(alpha: 0.6), width: 2),
                          ),
                          child: const Icon(Icons.cast_connected, color: _accentBlue, size: 36),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'CAMERA NODE STANDBY',
                          style: TextStyle(color: Colors.white, fontSize: 16,
                              fontWeight: FontWeight.w700, letterSpacing: 2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Frame the patient. Waiting for remote start...',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                        ),
                        const SizedBox(height: 48),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF003366).withValues(alpha: 0.5),
                              border: Border.all(color: _accentBlue.withValues(alpha: 0.4)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Text('Exit Camera Mode',
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (!isWaiting && session != null) ...[
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.88),
                    padding: const EdgeInsets.fromLTRB(18, 48, 18, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_formatName(session.studentName)} — ${session.injectionType} Injection',
                                style: const TextStyle(color: Color(0xFF003366), fontSize: 16,
                                    fontWeight: FontWeight.w700, height: 1.2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 7, height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _accentBlue,
                                      boxShadow: [BoxShadow(color: _accentBlue.withValues(alpha: 0.25), blurRadius: 0, spreadRadius: 3)],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${session.phase.toUpperCase().replaceAll("_", " ")} PHASE ACTIVE',
                                    style: const TextStyle(color: _accentBlue, fontSize: 11,
                                        fontWeight: FontWeight.w700, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (!isWaiting && session != null)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.90),
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 7, height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _detectionLost ? const Color(0xFF991B1B) : const Color(0xFF003366),
                                    boxShadow: [BoxShadow(
                                      color: (_detectionLost ? const Color(0xFF991B1B) : const Color(0xFF003366)).withValues(alpha: 0.25),
                                      blurRadius: 0, spreadRadius: 3)],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _detectionLost ? 'DETECTION LOST' : 'TRACKING ACTIVE',
                                  style: TextStyle(
                                    color: _detectionLost ? const Color(0xFF991B1B) : const Color(0xFF003366),
                                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF991B1B).withValues(alpha: 0.3),
                                border: Border.all(color: const Color(0xFF991B1B).withValues(alpha: 0.5)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('\u25cf REC',
                                  style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 10,
                                      fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildMetricCard('Phase',
                              session.phase.split('_')[0],
                              const Color(0xFF003366)),
                            /*
                            const SizedBox(width: 8),
                            _buildMetricCard('Angle',
                              _detectionLost ? '---' : '${_liveAngle.toStringAsFixed(1)}°',
                              _detectionLost ? Colors.white38 : Colors.white),
                            const SizedBox(width: 8),
                            _buildMetricCard('Score',
                              _detectionLost ? '-' : '$_liveScore/5',
                              _liveScore >= 4 ? _green : _liveScore >= 2 ? const Color(0xFFFCD34D) : _red),
                            */
                          ],
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () {
                            _liveService.clearSession(instructorId);
                            Navigator.pop(context);
                          },
                          child: Container(
                            width: double.infinity, height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF003366).withValues(alpha: 0.35),
                              border: Border.all(color: _accentBlue.withValues(alpha: 0.2)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.string(
                                  '<svg width="15" height="15" viewBox="0 0 15 15" fill="none"><path d="M10 7.5H3M6 4.5L3 7.5L6 10.5" stroke="rgba(255,255,255,0.55)" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 3h4v9H8" stroke="rgba(255,255,255,0.55)" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                                ),
                                const SizedBox(width: 7),
                                Text('Exit Camera Mode',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55),
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
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

  Widget _buildMetricCard(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: _accentBlue.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(value,
              style: TextStyle(color: valueColor, fontSize: 15,
                  fontWeight: FontWeight.w700, fontFamily: 'DM Mono')),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCornerGuides() {
    const color = _accentBlue;
    const opacity = 0.5;
    final c = color.withValues(alpha: opacity);
    return [
      Positioned(top: 120, left: 16,
        child: Container(width: 26, height: 26,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c, width: 2), left: BorderSide(color: c, width: 2)),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(4))))),
      Positioned(top: 120, right: 16,
        child: Container(width: 26, height: 26,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c, width: 2), right: BorderSide(color: c, width: 2)),
            borderRadius: const BorderRadius.only(topRight: Radius.circular(4))))),
      Positioned(bottom: 180, left: 16,
        child: Container(width: 26, height: 26,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c, width: 2), left: BorderSide(color: c, width: 2)),
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(4))))),
      Positioned(bottom: 180, right: 16,
        child: Container(width: 26, height: 26,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c, width: 2), right: BorderSide(color: c, width: 2)),
            borderRadius: const BorderRadius.only(bottomRight: Radius.circular(4))))),
    ];
  }
}
