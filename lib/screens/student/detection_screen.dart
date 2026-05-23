import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../../services/hand_landmark_service.dart';
import 'package:provider/provider.dart';
import '../../providers/session_state_provider.dart';
import '../../widgets/angle_overlay_painter.dart';
import '../../services/detection_service.dart';
import '../../services/aspiration_detection_service.dart';
import 'session_complete_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum DetectionPhase { insertion, aspiration, withdrawal }

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
  int _sensorOrientation = 90;

  // ── Hand Landmarker ──
  final HandLandmarkService _landmarkService = HandLandmarkService();
  bool _processing = false;
  List<Hand> _hands = [];

  // ── Phase & Tracking States ──
  DetectionPhase _phase = DetectionPhase.insertion;
  bool _isTrackingLost = false;

  // ── Insertion ──
  double _liveAngle = 0;
  bool _angleInRange = false;
  double? _lockedInsertionAngle;

  // ── Aspiration ──
  bool _aspirationStarted = false;
  bool _aspirationLocked = false;
  final AspirationDetectionService _aspirationService = AspirationDetectionService();

  // ── Withdrawal ──
  double? _lockedWithdrawalAngle;
  bool _withdrawalLocked = false;

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
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  void _updateAngleState() {
    final config = context.read<SessionStateProvider>().currentConfig;
    if (config == null) return;
    final delta = (_liveAngle - config.targetAngle).abs();
    _angleInRange = delta <= config.tolerance;
  }

  void _onFrame(CameraImage image) async {
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
            _isTrackingLost = false;
            final angle = AngleComputationUtil.computeDartGripAngle(_hands, sensorOrientation: _sensorOrientation);
            if (angle >= 0) {
              _liveAngle = angle;
              _updateAngleState();
            }

            if (_phase == DetectionPhase.aspiration && _aspirationStarted && !_aspirationLocked) {
              _aspirationService.update(_hands, sensorOrientation: _sensorOrientation);
            }
          } else {
            _isTrackingLost = true;
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

  // Phase 1: Insertion
  void _lockInsertion() {
    final session = context.read<SessionStateProvider>();
    final config = session.currentConfig!;
    final score = _scoreAngle(_liveAngle, config.targetAngle);
    session.setInsertion(_liveAngle, score);
    setState(() {
      _lockedInsertionAngle = _liveAngle;
    });
  }

  void _proceedToAspiration() {
    AngleComputationUtil.resetSmoothing(); // fresh buffer for next phase
    setState(() {
      _phase = DetectionPhase.aspiration;
    });
  }

  // Phase 2: Aspiration
  void _startAspiration() {
    _aspirationService.reset();
    setState(() {
      _aspirationStarted = true;
    });
  }

  void _lockAspiration() {
    final session = context.read<SessionStateProvider>();

    if (_aspirationService.result == 'Not Detected') {
      session.setFlagged(true);
    }

    session.setAspiration(
      result: _aspirationService.result,
      duration: _aspirationService.duration,
      smoothness: _aspirationService.smoothness,
    );

    setState(() {
      _aspirationLocked = true;
    });
  }

  void _proceedToWithdrawal() {
    AngleComputationUtil.resetSmoothing(); // fresh buffer for withdrawal
    setState(() {
      _phase = DetectionPhase.withdrawal;
    });
  }

  // Phase 3: Withdrawal
  void _lockWithdrawal() {
    final session = context.read<SessionStateProvider>();
    final config = session.currentConfig!;
    final score = _scoreAngle(_liveAngle, config.targetAngle);
    final delta = (_liveAngle - (_lockedInsertionAngle ?? 0)).abs();
    final correspondence = delta <= 5.0 ? 'Matches' : 'Deviates';

    session.setWithdrawal(_liveAngle, score);
    session.setCorrespondence(correspondence, delta);

    final aspScore = session.aspirationResult == 'Correct' ? 5 : session.aspirationResult == 'Incorrect' ? 2 : 1;
    final overall = ((session.insertionScore! + session.withdrawalScore! + aspScore) / 3).round();
    session.setOverallScore(overall);

    setState(() {
      _lockedWithdrawalAngle = _liveAngle;
      _withdrawalLocked = true;
    });
  }

  void _completeSession() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SessionCompleteScreen()));
  }

  @override
  void dispose() {
    _camera?.stopImageStream();
    _camera?.dispose();
    _landmarkService.dispose();
    super.dispose();
  }

  bool _isPhaseLocked() {
    if (_phase == DetectionPhase.insertion) return _lockedInsertionAngle != null;
    if (_phase == DetectionPhase.aspiration) return _aspirationLocked;
    if (_phase == DetectionPhase.withdrawal) return _withdrawalLocked;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStateProvider>();
    final target = session.currentConfig?.targetAngle ?? 0;
    final isLocked = _isPhaseLocked();

    return Scaffold(
      backgroundColor: const Color(0xFFE8EDF2),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopNav(session),
            Expanded(child: _buildCameraViewport(session, target, isLocked)),
            _buildStatusStrip(isLocked),
            _buildGaugeSection(target, isLocked),
            _buildBottomPanel(session, isLocked),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNav(SessionStateProvider session) {
    String title;
    String subtitle;
    
    if (_isTrackingLost) {
      title = 'Detection Paused';
      subtitle = 'Insertion Angle · Tracking Lost';
    } else if (_phase == DetectionPhase.insertion && !_isPhaseLocked()) {
      title = 'Detection Active';
      subtitle = 'Insertion Angle · Live';
    } else if (_phase == DetectionPhase.insertion && _isPhaseLocked()) {
      title = 'Insertion Confirmed';
      subtitle = 'Insertion Angle · Locked & Scored';
    } else if (_phase == DetectionPhase.aspiration) {
      title = 'Aspiration Tracking';
      subtitle = 'Aspiration Motion · Live';
    } else {
      title = 'Withdrawal Confirmed';
      subtitle = 'Withdrawal Angle · Locked & Scored';
    }

    final targetAngle = (session.currentConfig?.targetAngle ?? 0).toStringAsFixed(0);

    return Container(
      color: const Color(0xFF003366),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: SvgPicture.string(
                '''<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path d="M11 14L6 9L11 4" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>''',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFA8C4E0),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${widget.injectionType} $targetAngle°',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'DM Mono',
                letterSpacing: 0.04 * 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraViewport(SessionStateProvider session, double target, bool isLocked) {
    return Container(
      color: const Color(0xFF0D1F35),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Feed
          if (_cameraReady) CameraPreview(_camera!),

          // Corner Guides
          _buildCornerGuides(isLocked),

          // Tracking Lost Overlay
          if (_isTrackingLost)
            Container(
              color: const Color(0xFF080F1C).withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1928).withValues(alpha: 0.92),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.45), width: 1.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.string(
                      '''<svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
                        <path d="M24 19v10M24 33h.02M21.8 7.6L4 39a3 3 0 0 0 2.6 4.5H41.4A3 3 0 0 0 44 39L26.2 7.6a2.6 2.6 0 0 0-4.4 0z" stroke="#EF4444" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
                      </svg>'''
                    ),
                    const SizedBox(height: 10),
                    const Text('Detection Lost', style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text(
                      'Hand landmarks could not be tracked. Adjust hand position and ensure the hand and syringe are clearly visible.',
                      style: TextStyle(color: Color(0xFFA8C4E0), fontSize: 13, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => setState(() => _isTrackingLost = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.string(
                              '''<svg width="15" height="15" viewBox="0 0 15 15" fill="none" xmlns="http://www.w3.org/2000/svg">
                                <path d="M2 7.5a5.5 5.5 0 1 1 1.4 3.6" stroke="white" stroke-width="1.5" stroke-linecap="round"/>
                                <path d="M2 11V7.5h3.5" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                              </svg>'''
                            ),
                            const SizedBox(width: 6),
                            const Text('Resume Tracking', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Skeletons
            if (_hands.isNotEmpty)
              CustomPaint(painter: AngleOverlayPainter(hands: _hands, sensorOrientation: _sensorOrientation)),

            if (isLocked) ...[
              Container(color: const Color(0xFF22C55E).withValues(alpha: 0.07)),
              Center(
                child: FractionalTranslation(
                  translation: const Offset(0, -0.1),
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.5), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: SvgPicture.string(
                      '''<svg width="32" height="32" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
                        <path d="M7 16l6 6 12-12" stroke="#22C55E" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
                      </svg>'''
                    ),
                  ),
                ),
              ),
            ],
          ],

          // Angle Pill (Center Top)
          Positioned(
            top: 16, left: 0, right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildAnglePill(),
            ),
          ),

          // Info Pills
          Positioned(
            top: 16, left: 16,
            child: _buildInfoPillLeft(target),
          ),
          Positioned(
            top: 16, right: 16,
            child: _buildInfoPillRight(target, session),
          ),
        ],
      ),
    );
  }

  Widget _buildAnglePill() {
    Color bg;
    Color border;
    String numVal;
    Color numColor;
    String tag;
    Color tagColor;

    if (_isTrackingLost) {
      bg = const Color(0xFF003366).withValues(alpha: 0.85);
      border = const Color(0xFFEF4444).withValues(alpha: 0.35);
      numVal = _liveAngle.toStringAsFixed(0);
      numColor = const Color(0xFFFCA5A5);
      tag = 'PAUSED';
      tagColor = const Color(0xFFFCA5A5).withValues(alpha: 0.8);
    } else if (_phase == DetectionPhase.insertion && !_isPhaseLocked()) {
      bg = const Color(0xFF003366).withValues(alpha: 0.85);
      border = const Color(0xFFA8C4E0).withValues(alpha: 0.35);
      numVal = _liveAngle.toStringAsFixed(0);
      numColor = const Color(0xFF22C55E);
      tag = 'LIVE';
      tagColor = const Color(0xFFA8C4E0).withValues(alpha: 0.8);
    } else if (_phase == DetectionPhase.insertion && _isPhaseLocked()) {
      bg = const Color(0xFF22C55E).withValues(alpha: 0.2);
      border = const Color(0xFF22C55E).withValues(alpha: 0.55);
      numVal = (_lockedInsertionAngle ?? _liveAngle).toStringAsFixed(0);
      numColor = const Color(0xFF22C55E);
      tag = '🔒 LOCKED';
      tagColor = const Color(0xFF22C55E);
    } else if (_phase == DetectionPhase.aspiration) {
      bg = const Color(0xFF003366).withValues(alpha: 0.85);
      border = const Color(0xFF06B6D4).withValues(alpha: 0.4);
      numVal = _aspirationService.duration.toStringAsFixed(1);
      numColor = const Color(0xFF06B6D4);
      tag = 'SEC';
      tagColor = const Color(0xFFA8C4E0).withValues(alpha: 0.8);
    } else { // withdrawal
      bg = const Color(0xFF22C55E).withValues(alpha: 0.2);
      border = const Color(0xFF22C55E).withValues(alpha: 0.55);
      numVal = (_lockedWithdrawalAngle ?? _liveAngle).toStringAsFixed(0);
      numColor = const Color(0xFF22C55E);
      tag = '🔒 LOCKED';
      tagColor = const Color(0xFF22C55E);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(numVal, style: TextStyle(fontFamily: 'DM Mono', fontSize: 26, fontWeight: FontWeight.w600, color: numColor, height: 1)),
          if (_phase != DetectionPhase.aspiration)
            const Text('°', style: TextStyle(fontFamily: 'DM Mono', fontSize: 14, color: Color(0xFFA8C4E0))),
          const SizedBox(width: 4),
          Text(tag, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.07 * 10, color: tagColor)),
        ],
      ),
    );
  }

  Widget _buildInfoPillLeft(double target) {
    String val; String lbl; Color valColor;
    if (_phase == DetectionPhase.aspiration) {
      val = '${_aspirationService.displacement.toStringAsFixed(0)}px'; lbl = 'DISP.'; valColor = const Color(0xFF06B6D4);
    } else if (_phase == DetectionPhase.withdrawal) {
      val = widget.injectionType; lbl = 'TYPE'; valColor = const Color(0xFFA8C4E0);
    } else if (_isPhaseLocked()) {
      val = widget.injectionType; lbl = 'TYPE'; valColor = const Color(0xFFA8C4E0);
    } else {
      val = '${target.toStringAsFixed(0)}°'; lbl = 'TARGET'; valColor = const Color(0xFFA8C4E0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        border: Border.all(color: const Color(0xFFA8C4E0).withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(val, style: TextStyle(fontFamily: 'DM Mono', fontSize: 14, fontWeight: FontWeight.w600, color: valColor)),
          Text(lbl, style: TextStyle(fontSize: 9, color: const Color(0xFFA8C4E0).withValues(alpha: 0.55), letterSpacing: 0.07 * 9)),
        ],
      ),
    );
  }

  Widget _buildInfoPillRight(double target, SessionStateProvider session) {
    String val; String lbl; Color valColor;
    if (_phase == DetectionPhase.aspiration) {
      val = _aspirationService.smoothness; lbl = 'SMOOTH'; valColor = const Color(0xFF22C55E);
    } else if (_phase == DetectionPhase.withdrawal) {
      val = session.correspondenceResult ?? 'Match'; lbl = 'CORRESPOND.'; valColor = const Color(0xFF22C55E);
    } else if (_isPhaseLocked()) {
      val = '${session.insertionScore}/5'; lbl = 'SCORE'; valColor = const Color(0xFF22C55E);
    } else {
      double delta = _liveAngle - target;
      val = '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}°'; 
      lbl = _isTrackingLost ? 'LAST Δ' : 'DEV Δ'; 
      valColor = _isTrackingLost ? const Color(0xFFA8C4E0).withValues(alpha: 0.4) : const Color(0xFFF59E0B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        border: Border.all(color: const Color(0xFFA8C4E0).withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(val, style: TextStyle(fontFamily: 'DM Mono', fontSize: 14, fontWeight: FontWeight.w600, color: valColor)),
          Text(lbl, style: TextStyle(fontSize: 9, color: const Color(0xFFA8C4E0).withValues(alpha: 0.55), letterSpacing: 0.07 * 9)),
        ],
      ),
    );
  }

  Widget _buildCornerGuides(bool isLocked) {
    Color guideColor;
    if (_isTrackingLost) guideColor = const Color(0xFFEF4444).withValues(alpha: 0.5);
    else if (_phase == DetectionPhase.aspiration) guideColor = const Color(0xFF06B6D4).withValues(alpha: 0.55);
    else if (isLocked) guideColor = const Color(0xFF22C55E).withValues(alpha: 0.8);
    else guideColor = const Color(0xFFA8C4E0).withValues(alpha: 0.6);

    return Stack(
      children: [
        Positioned(top: 20, left: 20, child: Container(width: 26, height: 26, decoration: BoxDecoration(border: Border(top: BorderSide(color: guideColor, width: 2.5), left: BorderSide(color: guideColor, width: 2.5))))),
        Positioned(top: 20, right: 20, child: Container(width: 26, height: 26, decoration: BoxDecoration(border: Border(top: BorderSide(color: guideColor, width: 2.5), right: BorderSide(color: guideColor, width: 2.5))))),
        Positioned(bottom: 20, left: 20, child: Container(width: 26, height: 26, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: guideColor, width: 2.5), left: BorderSide(color: guideColor, width: 2.5))))),
        Positioned(bottom: 20, right: 20, child: Container(width: 26, height: 26, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: guideColor, width: 2.5), right: BorderSide(color: guideColor, width: 2.5))))),
      ],
    );
  }

  Widget _buildStatusStrip(bool isLocked) {
    Color bg; Color border; Color dotColor; Color textColor; String text;
    if (_isTrackingLost) {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.1); border = const Color(0xFFEF4444).withValues(alpha: 0.3); dotColor = const Color(0xFFEF4444); textColor = const Color(0xFFFCA5A5);
      text = 'Landmarks Not Detected — Adjust Hand Position';
    } else if (_phase == DetectionPhase.insertion && !_isPhaseLocked()) {
      bg = const Color(0xFF22C55E).withValues(alpha: 0.12); border = const Color(0xFF22C55E).withValues(alpha: 0.3); dotColor = const Color(0xFF22C55E); textColor = const Color(0xFF22C55E);
      text = 'Landmarks Detected — Tracking Active';
    } else if (_phase == DetectionPhase.insertion && _isPhaseLocked()) {
      bg = const Color(0xFF22C55E).withValues(alpha: 0.12); border = const Color(0xFF22C55E).withValues(alpha: 0.3); dotColor = const Color(0xFF22C55E); textColor = const Color(0xFF22C55E);
      text = 'Angle Locked — ${_lockedInsertionAngle?.toStringAsFixed(0)}° Recorded to Session State';
    } else if (_phase == DetectionPhase.aspiration) {
      bg = const Color(0xFF06B6D4).withValues(alpha: 0.1); border = const Color(0xFF06B6D4).withValues(alpha: 0.28); dotColor = const Color(0xFF06B6D4); textColor = const Color(0xFF06B6D4);
      text = 'L4 Thumb Tracked — Withdrawal in Progress';
    } else {
      bg = const Color(0xFF22C55E).withValues(alpha: 0.12); border = const Color(0xFF22C55E).withValues(alpha: 0.3); dotColor = const Color(0xFF22C55E); textColor = const Color(0xFF22C55E);
      text = 'Withdrawal Angle Locked — ${_lockedWithdrawalAngle?.toStringAsFixed(0)}° Recorded to Session State';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(color: bg, border: Border(top: BorderSide(color: border))),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.5), blurRadius: 4)])),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.02 * 12)),
        ],
      ),
    );
  }

  Widget _buildGaugeSection(double target, bool isLocked) {
    String label; String score; Color scoreBg; Color scoreColor; double fillPercent;
    List<Color> gradientColors; String markerLabel; double markerPct;

    if (_phase == DetectionPhase.aspiration) {
      label = 'ASPIRATION DURATION';
      score = '${_aspirationService.duration.toStringAsFixed(1)}s / ≥2s threshold';
      scoreBg = const Color(0xFF06B6D4).withValues(alpha: 0.2); scoreColor = const Color(0xFF06B6D4);
      fillPercent = _aspirationService.duration / 3.0; // Assume 3s max on gauge
      gradientColors = const [Color(0xFF06B6D4), Color(0xFF67E8F9)];
      markerLabel = 'Min 2s'; markerPct = 2.0 / 3.0;
    } else {
      label = _phase == DetectionPhase.withdrawal ? 'WITHDRAWAL ANGLE' : 'INSERTION ANGLE';
      double displayAngle = _isPhaseLocked() ? ((_phase == DetectionPhase.insertion ? _lockedInsertionAngle : _lockedWithdrawalAngle) ?? _liveAngle) : _liveAngle;
      
      if (_isTrackingLost) {
        score = 'Paused — Last: ${displayAngle.toStringAsFixed(0)}°';
        scoreBg = const Color(0xFFEF4444).withValues(alpha: 0.2); scoreColor = const Color(0xFFFCA5A5);
        gradientColors = [const Color(0xFFEF4444).withValues(alpha: 0.35), const Color(0xFFEF4444).withValues(alpha: 0.35)];
      } else if (isLocked) {
        int s = _scoreAngle(displayAngle, target);
        score = '${displayAngle.toStringAsFixed(0)}° ✓ Scored $s/5';
        scoreBg = const Color(0xFF22C55E).withValues(alpha: 0.2); scoreColor = const Color(0xFF22C55E);
        gradientColors = const [Color(0xFF22C55E), Color(0xFF86EFAC)];
      } else {
        score = '${displayAngle.toStringAsFixed(0)}° / ${target.toStringAsFixed(0)}° target';
        scoreBg = const Color(0xFF22C55E).withValues(alpha: 0.2); scoreColor = const Color(0xFF22C55E);
        gradientColors = const [Color(0xFF22C55E), Color(0xFF86EFAC)];
      }
      fillPercent = displayAngle / 180.0;
      markerLabel = '${target.toStringAsFixed(0)}°'; markerPct = target / 180.0;
    }

    return Container(
      color: const Color(0xFF002244),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFFA8C4E0), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: scoreBg, borderRadius: BorderRadius.circular(6)),
                child: Text(score, style: TextStyle(color: scoreColor, fontSize: 11, fontWeight: FontWeight.w700)),
              )
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(height: 8, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4))),
              FractionallySizedBox(
                widthFactor: fillPercent.clamp(0.0, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradientColors),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Positioned(
                left: MediaQuery.of(context).size.width * markerPct - 20,
                top: -4,
                child: Column(
                  children: [
                    Text(markerLabel, style: const TextStyle(fontFamily: 'DM Mono', fontSize: 9, color: Color(0xFFA8C4E0))),
                    const SizedBox(height: 2),
                    Container(width: 2, height: 16, color: const Color(0xFFA8C4E0), margin: const EdgeInsets.only(top: -6)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 4),
          if (_phase != DetectionPhase.aspiration)
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0°', style: TextStyle(fontFamily: 'DM Mono', fontSize: 9, color: Colors.white38)),
                Text('45°', style: TextStyle(fontFamily: 'DM Mono', fontSize: 9, color: Colors.white38)),
                Text('90°', style: TextStyle(fontFamily: 'DM Mono', fontSize: 9, color: Colors.white38)),
                Text('135°', style: TextStyle(fontFamily: 'DM Mono', fontSize: 9, color: Colors.white38)),
                Text('180°', style: TextStyle(fontFamily: 'DM Mono', fontSize: 9, color: Colors.white38)),
              ],
            )
        ],
      ),
    );
  }

  Widget _buildBottomPanel(SessionStateProvider session, bool isLocked) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isTrackingLost) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  SvgPicture.string('''<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M9 7.5v3M9 12h.01M7.5 2.5L1 14h16L10.5 2.5a1.73 1.73 0 0 0-3 0z" stroke="#EF4444" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>'''),
                  const SizedBox(width: 10),
                  const Expanded(child: Text("Angle recording is suspended until landmarks are re-acquired.", style: TextStyle(color: Color(0xFFB91C1C), fontSize: 11.5, height: 1.45))),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (isLocked) _buildScoreCard(session) else _buildRubricRow(),

          Container(height: 1, color: const Color(0xFF003366).withValues(alpha: 0.07), margin: const EdgeInsets.symmetric(vertical: 14)),

          _buildActionButton(session),
        ],
      ),
    );
  }

  Widget _buildRubricRow() {
    String phase; String desc;
    if (_isTrackingLost) {
      phase = 'Phase 1 — Insertion'; desc = 'Tracking paused — awaiting re-acquisition';
    } else if (_phase == DetectionPhase.insertion) {
      phase = 'Phase 1 — Insertion'; desc = 'Awaiting needle insertion confirmation';
    } else if (_phase == DetectionPhase.aspiration) {
      phase = 'Phase 2 — Aspiration'; desc = 'Aspirating... tracking L4 thumb displacement';
    } else {
      phase = 'Phase 3 — Withdrawal'; desc = 'Awaiting withdrawal angle lock';
    }

    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: const Color(0xFFEFF7FF), borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: SvgPicture.string('''<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M9 2v10M4 9l5 6 5-6" stroke="#003366" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>'''),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(phase, style: const TextStyle(color: Color(0xFF1A2E4A), fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 1),
              Text(desc, style: const TextStyle(color: Color(0xFF4A6080), fontSize: 11)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFFEFF7FF), borderRadius: BorderRadius.circular(8)),
          child: const Text('In Progress', style: TextStyle(color: Color(0xFF003366), fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _buildScoreCard(SessionStateProvider session) {
    int score = 0; String title = ''; String desc = '';
    if (_phase == DetectionPhase.insertion) {
      score = session.insertionScore ?? 0;
      title = 'Insertion Angle: ${(_lockedInsertionAngle ?? 0).toStringAsFixed(0)}°';
      desc = 'Within ±${session.currentConfig?.tolerance ?? 0}° of ${session.currentConfig?.targetAngle ?? 0}° target. CIT-U Rubric: $score/5';
    } else if (_phase == DetectionPhase.aspiration) {
      score = session.aspirationResult == 'Correct' ? 5 : session.aspirationResult == 'Incorrect' ? 2 : 1;
      title = 'Aspiration: ${session.aspirationResult}';
      desc = 'Duration: ${_aspirationService.duration.toStringAsFixed(1)}s. Rubric: $score/5';
    } else {
      score = session.withdrawalScore ?? 0;
      title = 'Withdrawal Angle: ${(_lockedWithdrawalAngle ?? 0).toStringAsFixed(0)}°';
      desc = 'Matches insertion angle (${(_lockedInsertionAngle ?? 0).toStringAsFixed(0)}°). Δ = ${session.angularDelta?.toStringAsFixed(0)}°. CIT-U Rubric: $score/5';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: const Color(0xFF22C55E).withValues(alpha: 0.15), border: Border.all(color: const Color(0xFF22C55E), width: 2.5), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(score.toString(), style: const TextStyle(fontFamily: 'DM Mono', color: Color(0xFF166534), fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF166534), fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: Color(0xFF166534), fontSize: 12, height: 1.4)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButton(SessionStateProvider session) {
    if (_isTrackingLost) {
      return Column(
        children: [
          _ActionButton(
            label: 'Adjust Position & Resume',
            iconSvg: '''<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 9v4M12 17h.01M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>''',
            onPressed: () => setState(() => _isTrackingLost = false),
          ),
        ],
      );
    }

    if (_phase == DetectionPhase.insertion) {
      if (!_isPhaseLocked()) {
        return Column(
          children: [
            _ActionButton(key: const Key('lock_insertion_button'), label: 'Confirm Needle Insertion', iconSvg: '''<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M5 12l4 4L19 8" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>''', onPressed: _angleInRange ? _lockInsertion : null),
            const SizedBox(height: 8), const Text('Tap when the needle is visibly inserted at the correct angle', style: TextStyle(color: Color(0xFF4A6080), fontSize: 11)),
          ],
        );
      } else {
        return _ActionButton(key: const Key('proceed_aspiration_button'), label: 'Proceed to Aspiration Detection', iconSvg: '''<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M5 12h14M12 5l7 7-7 7" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>''', onPressed: _proceedToAspiration);
      }
    } else if (_phase == DetectionPhase.aspiration) {
      if (!_aspirationStarted) {
        return _ActionButton(key: const Key('start_aspiration_button'), label: 'Start Aspiration', iconSvg: '''<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M5 12h14M12 5l7 7-7 7" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>''', onPressed: _startAspiration);
      } else if (!_aspirationLocked) {
        return Column(
          children: [
            _ActionButton(key: const Key('lock_aspiration_button'), label: 'Done Aspirating (${_aspirationService.duration.toStringAsFixed(1)}s)', iconSvg: '''<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="4" y="4" width="16" height="16" rx="3" stroke="white" stroke-width="1.8"/><rect x="8" y="8" width="8" height="8" rx="1" fill="white"/></svg>''', onPressed: _aspirationService.duration >= 1.0 || _aspirationService.result == 'Not Detected' ? _lockAspiration : null),
            const SizedBox(height: 8), const Text('Tap when plunger withdrawal is fully complete', style: TextStyle(color: Color(0xFF4A6080), fontSize: 11)),
          ],
        );
      } else {
        return _ActionButton(key: const Key('proceed_withdrawal_button'), label: 'Proceed to Withdrawal', iconSvg: '''<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M5 12h14M12 5l7 7-7 7" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>''', onPressed: _proceedToWithdrawal);
      }
    } else {
      if (!_withdrawalLocked) {
        return _ActionButton(key: const Key('lock_withdrawal_button'), label: 'Confirm Withdrawal Angle', iconSvg: '''<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M5 12l4 4L19 8" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>''', onPressed: _angleInRange ? _lockWithdrawal : null);
      } else {
        return _ActionButton(key: const Key('complete_session_button'), label: 'Complete Session', iconSvg: '''<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4 12l4 4L20 6" stroke="white" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>''', onPressed: _completeSession, color: const Color(0xFF22C55E));
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final String iconSvg;
  final VoidCallback? onPressed;
  final Color color;

  const _ActionButton({super.key, required this.label, required this.iconSvg, this.onPressed, this.color = const Color(0xFF003366)});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        key: key,
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.string(iconSvg),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
