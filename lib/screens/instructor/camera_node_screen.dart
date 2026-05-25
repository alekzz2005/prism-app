import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/user_role_provider.dart';
import '../../services/roboflow_service.dart';
import '../../services/live_session_service.dart';

// ─── Brand Colours ─────────────────────────────────────────────────────────
const _accentBlue = Color(0xFFA8C4E0);
const _green      = Color(0xFF4ADE80);
const _greenDark  = Color(0xFF22C55E);
const _red        = Color(0xFFF87171);
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
  int    _liveScore = 0;
  String _currentPhase = 'waiting';
  Size? _imageSize;
  LiveSessionModel? _currentSession;

  Timer? _syncTimer;
  double? _lastInsertionAngle;
  String? _instructorId;

  // Roboflow detection state
  bool _detectionLost = false;
  CameraImage? _latestFrame;

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
    RoboflowDetectionService.resetSmoothing();
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
      
      if (_instructorId != null) {
        _liveService.setCameraActive(_instructorId!, true);
      }
      
      // 2Hz sync timer — sends latest frame to Roboflow every 500ms
      _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _syncMetrics());
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  // ─── 2Hz Sync ─────────────────────────────────────────────────────────────
  void _syncMetrics() async {
    if (!mounted) return;
    
    final instructorId = _instructorId;
    if (instructorId == null) return;

    if (_currentPhase == 'waiting' || _currentPhase == 'completed') return;

    // Grab the cached frame
    final frame = _latestFrame;
    if (frame == null) {
      _liveService.setDetectionLost(instructorId, true);
      return;
    }

    // Send to Roboflow (or mock) and get angle result
    final result = await RoboflowDetectionService.detectAngle(frame);

    if (!mounted) return;

    setState(() {
      _detectionLost = result.detectionLost;
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

  // ─── Frame Caching ────────────────────────────────────────────────────────
  // We only cache the latest frame; the heavy work is done in _syncMetrics.
  void _onFrame(CameraImage image) {
    if (_currentPhase == 'waiting' || _currentPhase == 'completed') return;
    _latestFrame = image;
    
    if (mounted) {
      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    }
  }

  // ─── Scoring ──────────────────────────────────────────────────────────────
  int _scoreAngle(double measured, double target) {
    return RoboflowDetectionService.scoreIMAngle(measured);
  }

  void _handlePhaseChange(String instructorId, LiveSessionModel session, String oldPhase) {
    if (session.phase == oldPhase) return;
    _currentPhase = session.phase;

    if (session.phase == 'waiting' || session.phase == 'completed') {
      setState(() {
        _lastInsertionAngle = null;
        _detectionLost = false;
      });
      RoboflowDetectionService.resetSmoothing();
    } else if (session.phase == 'insertion_locked' && oldPhase == 'insertion') {
      final score = _scoreAngle(_liveAngle, session.targetAngle);
      _lastInsertionAngle = _liveAngle;
      _liveService.saveInsertionMetrics(instructorId, _liveAngle, score);
    } else if (session.phase == 'aspiration' && oldPhase == 'insertion_locked') {
      RoboflowDetectionService.resetSmoothing();
    } else if (session.phase == 'aspiration_locked' && oldPhase == 'aspiration') {
      RoboflowDetectionService.resetSmoothing();
    } else if (session.phase == 'withdrawal' && oldPhase == 'aspiration_locked') {
      RoboflowDetectionService.resetSmoothing();
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
                RoboflowDetectionService.resetSmoothing();
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
                        ],
                      ),
                    ),
                  ),
                ),

              if (!isWaiting) ..._buildCornerGuides(),

              // ── Detection Lost Overlay ──
              if (!isWaiting && _detectionLost)
                Positioned.fill(
                  child: Container(
                    color: Colors.red.withValues(alpha: 0.15),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _red.withValues(alpha: 0.6), width: 2),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: _red, size: 40),
                            const SizedBox(height: 10),
                            const Text(
                              'DETECTION LOST',
                              style: TextStyle(color: Colors.white, fontSize: 16,
                                  fontWeight: FontWeight.w800, letterSpacing: 2),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Syringe or arm not visible.\nReposition the camera.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

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
                                style: const TextStyle(color: Colors.white, fontSize: 16,
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
                                    color: _detectionLost ? _red : _greenDark,
                                    boxShadow: [BoxShadow(
                                      color: (_detectionLost ? _red : _greenDark).withValues(alpha: 0.25),
                                      blurRadius: 0, spreadRadius: 3)],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _detectionLost ? 'DETECTION LOST' : 'TRACKING ACTIVE',
                                  style: TextStyle(
                                    color: _detectionLost ? _red : _green,
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
                              const Color(0xFFFCD34D)),
                            const SizedBox(width: 8),
                            _buildMetricCard('Angle',
                              _detectionLost ? '---' : '${_liveAngle.toStringAsFixed(1)}°',
                              _detectionLost ? Colors.white38 : Colors.white),
                            const SizedBox(width: 8),
                            _buildMetricCard('Score',
                              _detectionLost ? '-' : '$_liveScore/5',
                              _liveScore >= 4 ? _green : _liveScore >= 2 ? const Color(0xFFFCD34D) : _red),
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
