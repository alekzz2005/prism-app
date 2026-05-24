import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;

import '../../providers/user_role_provider.dart';
import '../../services/hand_landmark_service.dart';
import '../../services/detection_service.dart';
import '../../services/aspiration_detection_service.dart';
import '../../services/live_session_service.dart';
import '../../widgets/angle_overlay_painter.dart';

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

  final HandLandmarkService _landmarkService = HandLandmarkService();
  bool _processing = false;
  List<Hand> _hands = [];
  final LiveSessionService _liveService = LiveSessionService();
  final AspirationDetectionService _aspirationService = AspirationDetectionService();

  double _liveAngle = 0;
  String _currentPhase = 'waiting';
  Size? _imageSize;
  LiveSessionModel? _currentSession;

  Timer? _syncTimer;
  double? _lastInsertionAngle;
  math.Point<double>? _lockedWristPos;
  String? _instructorId;  // cached to avoid context.read in dispose/timers

  @override
  void initState() {
    super.initState();
    // Cache instructorId so dispose() and timers don't need context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _instructorId = context.read<UserRoleProvider>().uid;
      
      // Defer heavy initialization until after the route transition finishes
      // This prevents the dashboard button from freezing when clicked.
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
    _landmarkService.dispose();
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
      await _camera!.startImageStream(_onFrame);
      if (mounted) setState(() => _cameraReady = true);
      
      // Delay ML initialization so the camera preview can render smoothly first
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        // Enable tracking for 2 hands so Aspiration can track the plunger pull!
        _landmarkService.init(minConfidence: 0.01, numHands: 2);
      });
      
      // Notify remote control that camera is now active
      if (_instructorId != null) {
        _liveService.setCameraActive(_instructorId!, true);
      }
      
      // Start 2Hz sync timer
      _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _syncMetrics());
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  void _syncMetrics() {
    if (!mounted) return;
    // Wait for insertion or withdrawal or aspiration
    if (_currentPhase != 'insertion' && _currentPhase != 'withdrawal' && _currentPhase != 'aspiration') return;
    if (_liveAngle < 0 && _currentPhase != 'aspiration') return;
    final instructorId = _instructorId;
    if (instructorId == null) return;

    // Sync detection state
    bool isLost = _hands.isEmpty;
    _liveService.setDetectionLost(instructorId, isLost);

    if (_currentPhase == 'insertion' || _currentPhase == 'withdrawal') {
      if (_liveAngle >= 0) {
        _liveService.updateLiveAngle(instructorId, _liveAngle);
      }
    } else if (_currentPhase == 'aspiration') {
      _liveService.updateLiveAspiration(instructorId, _aspirationService.result, _aspirationService.duration);
    }
  }

  List<Hand> _sortAndLockActiveHand(List<Hand> detectedHands) {
    if (detectedHands.isEmpty) return detectedHands;

    List<Hand> candidateHands = List.from(detectedHands);
    Hand? activeHand;

    // 1. Try to maintain existing lock on the instructor's hand
    if (_lockedWristPos != null) {
      double minLockDist = double.infinity;
      for (final h in candidateHands) {
        final w = h.landmarks[0];
        final dist = math.pow(w.x - _lockedWristPos!.x, 2) + math.pow(w.y - _lockedWristPos!.y, 2);
        if (dist < minLockDist) {
          minLockDist = dist.toDouble();
          activeHand = h;
        }
      }

      if (minLockDist > 0.05) {
        _lockedWristPos = null; // Lock broken
        activeHand = null;
      }
    }

    // 2. If no lock, find the hand closest to the center of the screen
    if (_lockedWristPos == null && candidateHands.isNotEmpty) {
      double bestScore = double.infinity;
      for (final h in candidateHands) {
        final w = h.landmarks[0];
        // Center of normalized screen is (0.5, 0.5)
        double dx = w.x - 0.5;
        double dy = w.y - 0.5;
        double score = dx * dx + dy * dy;

        if (score < bestScore) { 
          bestScore = score;
          activeHand = h;
        }
      }
    }

    if (activeHand != null) {
      final w = activeHand.landmarks[0];
      _lockedWristPos = math.Point(w.x, w.y);

      final sorted = [activeHand];
      for (final h in detectedHands) {
        if (h != activeHand) sorted.add(h);
      }
      return sorted;
    } else {
      // If no valid active hand (e.g. only stabilizing hand detected), don't put it at index 0.
      // But we still want to draw it! 
      // We return an empty list so that the detection engine skips this frame, 
      // but we lose the drawing of the stabilizing hand. That's acceptable for correct tracking.
      return []; 
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing) return;
    if (_currentPhase == 'waiting') return;
    _processing = true;
    try {
      final cam = _camera?.description;
      if (cam == null) return;
      
      final sensorOrientation = cam.sensorOrientation;
      
      // Run hand model only
      final detectedHands = _landmarkService.detect(image, sensorOrientation);
      
      if (mounted) {
        setState(() {
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
          _hands = _sortAndLockActiveHand(detectedHands);
          _sensorOrientation = sensorOrientation;
          
          if (_hands.isNotEmpty && _currentSession != null) {
            final angle = AngleComputationUtil.computeAbsoluteInjectionAngle(
                _hands, _imageSize!, 
                injectionType: _currentSession!.injectionType, 
                sensorOrientation: _sensorOrientation);
                
            if (angle >= 0) _liveAngle = angle;
            
              if (_currentPhase == 'aspiration') {
                _aspirationService.update(_hands, sensorOrientation: _sensorOrientation);

                if (_aspirationService.isFinished) {
                  final instructorId = _instructorId;
                  if (instructorId != null) {
                    _liveService.saveAspirationMetrics(instructorId, _aspirationService.result,
                        _aspirationService.duration, _aspirationService.smoothness);
                    _liveService.updatePhase(instructorId, 'withdrawal');
                  }
                }
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
    } else if (session.phase == 'withdrawal' && oldPhase == 'aspiration') {
      // Manual override edge-case: If the instructor manually hits "override" on the remote
      // before the camera node auto-detects, we save whatever metrics we have currently.
      if (!_aspirationService.isFinished) {
        _liveService.saveAspirationMetrics(instructorId, _aspirationService.result,
            _aspirationService.duration, _aspirationService.smoothness);
      }
      AngleComputationUtil.resetSmoothing();
    } else if (session.phase == 'withdrawal_locked' && oldPhase == 'withdrawal') {
      final score = _scoreAngle(_liveAngle, session.targetAngle);
      final delta = (_liveAngle - (_lastInsertionAngle ?? 0)).abs();
      final corr  = delta <= 5.0 ? 'Matches' : 'Deviates';
      _liveService.saveWithdrawalMetrics(instructorId, _liveAngle, score, corr, delta);
    }
  }



  @override
  Widget build(BuildContext context) {
    final instructorId = context.watch<UserRoleProvider>().uid;
    // Keep cached ID up to date
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
                _aspirationService.reset();
                AngleComputationUtil.resetSmoothing();
              }
            });
          }

          final isWaiting = session == null || session.phase == 'waiting';
          final isTrackingActive = session != null && (session.phase == 'insertion' || session.phase == 'withdrawal');

          // ── Camera & Overlays ─────────────────────────────────────────────
          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera background – dark navy
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
                const Center(
                  child: CircularProgressIndicator(color: _accentBlue),
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
                          if (_hands.isNotEmpty && _imageSize != null)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: AngleOverlayPainter(
                                  hands: _hands,
                                  imageSize: _imageSize!,
                                  sensorOrientation: _sensorOrientation,
                                  injectionType: _currentSession?.injectionType,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Corner guides – accent blue
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
                if (_cameraReady && _currentPhase != 'waiting' && _hands.isEmpty)
                  Container(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 64),
                          SizedBox(height: 16),
                          Text('DETECTION LOST', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
                          Text('Please readjust hand or camera placement', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),

                // Top banner
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.88),
                    padding: const EdgeInsets.fromLTRB(18, 48, 18, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${session.studentName} \u2014 ${session.injectionType} Injection',
                              style: const TextStyle(color: Colors.white, fontSize: 16,
                                  fontWeight: FontWeight.w700, height: 1.2),
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
                        GestureDetector(
                          onTap: () {
                            _liveService.clearSession(instructorId);
                            Navigator.pop(context);
                          },
                          child: Container(
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: SvgPicture.string(
                              '<svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M3 3l8 8M11 3l-8 8" stroke="rgba(255,255,255,0.4)" stroke-width="1.5" stroke-linecap="round"/></svg>',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Angle chip – centered
              if (isTrackingActive)
                Align(
                  alignment: const Alignment(0, -0.2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      border: Border.all(color: _accentBlue.withValues(alpha: 0.3), width: 1.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Live Angle',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, height: 1.2)),
                        const SizedBox(height: 2),
                        Text('${_liveAngle.toStringAsFixed(0)}\u00b0',
                          style: const TextStyle(color: Colors.white, fontSize: 38,
                              fontWeight: FontWeight.w700, fontFamily: 'DM Mono', height: 1.1)),
                        const SizedBox(height: 2),
                        Text(
                          'Target: ${session.targetAngle.toStringAsFixed(0)}\u00b0 \u00b7 \u0394 ${(_liveAngle - session.targetAngle).abs().toStringAsFixed(0)}\u00b0',
                          style: const TextStyle(color: _accentBlue, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
                ),

              // Bottom status panel
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
                                    color: _greenDark,
                                    boxShadow: [BoxShadow(color: _greenDark.withValues(alpha: 0.25), blurRadius: 0, spreadRadius: 3)],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text('TRACKING ACTIVE',
                                    style: TextStyle(color: _green, fontSize: 11,
                                        fontWeight: FontWeight.w700, letterSpacing: 0.8)),
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
                            _buildMetricCard('Insertion Angle',
                              session.finalInsertionAngle != null
                                  ? '${session.finalInsertionAngle!.toStringAsFixed(1)}\u00b0'
                                  : '--',
                              _accentBlue),
                            const SizedBox(width: 10),
                            Text(
                              'H: ${_hands.isNotEmpty ? 21 : 0}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildMetricCard('Phase',
                              session.phase.split('_')[0],
                              const Color(0xFFFCD34D)),
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
