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
    final config = session.currentConfig;
    final target = config?.targetAngle ?? 0;
    final isLocked = _isPhaseLocked();

    return Scaffold(
      backgroundColor: const Color(0xFFE8EDF2),
      body: SafeArea(
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
    String title = "Detection Active";
    String subtitle = "Live";
    
    if (_isTrackingLost) {
      title = "Detection Paused";
      subtitle = "Tracking Lost";
    } else if (_isPhaseLocked()) {
      if (_phase == DetectionPhase.insertion) title = "Insertion Confirmed";
      if (_phase == DetectionPhase.aspiration) title = "Aspiration Completed";
      if (_phase == DetectionPhase.withdrawal) title = "Withdrawal Confirmed";
      subtitle = "Locked & Scored";
    }

    String phaseName = _phase == DetectionPhase.insertion ? "Insertion Angle" : 
                       _phase == DetectionPhase.aspiration ? "Aspiration Motion" : "Withdrawal Angle";

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
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$phaseName • $subtitle', style: const TextStyle(color: Color(0xFFA8C4E0), fontSize: 11)),
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
              '${widget.injectionType} ${(session.currentConfig?.targetAngle ?? 0).toStringAsFixed(0)}°',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraViewport(SessionStateProvider session, double target, bool isLocked) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Feed
        _cameraReady
            ? CameraPreview(_camera!)
            : Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D1F35), Color(0xFF0A1828), Color(0xFF111C2A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),

        // Corner Guides
        _buildCornerGuides(isLocked),

        if (_isTrackingLost) ...[
          // Tracking lost overlay
          Container(
            color: const Color(0xFF080F1C).withValues(alpha: 0.55),
            alignment: Alignment.center,
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1928).withValues(alpha: 0.92),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.45), width: 1.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 48),
                  const SizedBox(height: 12),
                  const Text('Detection Lost', style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Hand landmarks could not be tracked. Adjust hand position.', 
                             style: TextStyle(color: Color(0xFFA8C4E0), fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _isTrackingLost = false),
                    icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                    label: const Text('Simulate Resume', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                ],
              ),
            ),
          )
        ] else ...[
          // Skeletons
          if (_hands.isNotEmpty)
            CustomPaint(painter: AngleOverlayPainter(hands: _hands, sensorOrientation: _sensorOrientation)),

          if (isLocked)
            Container(color: const Color(0xFF22C55E).withValues(alpha: 0.07)),

          if (isLocked && _phase == DetectionPhase.insertion)
            Center(
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.5), width: 2),
                ),
                child: const Icon(Icons.check, color: Color(0xFF22C55E), size: 36),
              ),
            ),

          // Top Pills
          Positioned(
            top: 16, left: 16,
            child: _buildInfoPill('Target', '${target.toStringAsFixed(0)}°', Colors.black45, const Color(0xFFA8C4E0)),
          ),
          Positioned(
            top: 16, right: 16,
            child: _buildInfoPill('Dev Δ', '${(_liveAngle - target).toStringAsFixed(1)}°', Colors.black45, const Color(0xFFF59E0B)),
          ),
          Positioned(
            top: 16, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(
                  color: isLocked ? const Color(0xFF22C55E).withValues(alpha: 0.2) : const Color(0xFF003366).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isLocked ? const Color(0xFF22C55E).withValues(alpha: 0.55) : const Color(0xFFA8C4E0).withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (isLocked ? (_lockedInsertionAngle ?? _liveAngle) : _liveAngle).toStringAsFixed(0),
                      style: TextStyle(fontFamily: 'monospace', fontSize: 26, fontWeight: FontWeight.bold, color: isLocked ? const Color(0xFF22C55E) : const Color(0xFF22C55E)),
                    ),
                    const Text('°', style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: Color(0xFFA8C4E0))),
                    const SizedBox(width: 4),
                    Text(isLocked ? '🔒 LOCKED' : 'LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLocked ? const Color(0xFF22C55E) : const Color(0xFFA8C4E0))),
                  ],
                ),
              ),
            ),
          )
        ],
      ],
    );
  }

  Widget _buildCornerGuides(bool isLocked) {
    Color guideColor = _isTrackingLost ? const Color(0xFFEF4444).withValues(alpha: 0.5) :
                       isLocked ? const Color(0xFF22C55E).withValues(alpha: 0.8) :
                       const Color(0xFFA8C4E0).withValues(alpha: 0.6);
    return Stack(
      children: [
        Positioned(top: 20, left: 20, child: Container(width: 24, height: 24, decoration: BoxDecoration(border: Border(top: BorderSide(color: guideColor, width: 2.5), left: BorderSide(color: guideColor, width: 2.5))))),
        Positioned(top: 20, right: 20, child: Container(width: 24, height: 24, decoration: BoxDecoration(border: Border(top: BorderSide(color: guideColor, width: 2.5), right: BorderSide(color: guideColor, width: 2.5))))),
        Positioned(bottom: 20, left: 20, child: Container(width: 24, height: 24, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: guideColor, width: 2.5), left: BorderSide(color: guideColor, width: 2.5))))),
        Positioned(bottom: 20, right: 20, child: Container(width: 24, height: 24, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: guideColor, width: 2.5), right: BorderSide(color: guideColor, width: 2.5))))),
      ],
    );
  }

  Widget _buildInfoPill(String label, String value, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFA8C4E0).withValues(alpha: 0.2))),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildStatusStrip(bool isLocked) {
    Color bgColor = _isTrackingLost ? const Color(0xFFEF4444).withValues(alpha: 0.1) : 
                    isLocked ? const Color(0xFF22C55E).withValues(alpha: 0.12) : 
                    const Color(0xFF22C55E).withValues(alpha: 0.12);
    Color dotColor = _isTrackingLost ? const Color(0xFFEF4444) : const Color(0xFF22C55E);
    String text = _isTrackingLost ? "Landmarks Not Detected — Adjust Hand Position" : 
                  isLocked ? "Angle Locked — Recorded to Session State" : 
                  "Landmarks Detected — Tracking Active";
    
    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.7), blurRadius: 6)])),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: dotColor, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildGaugeSection(double target, bool isLocked) {
    double fillPercent = (_isTrackingLost ? (_lockedInsertionAngle ?? _liveAngle) : _liveAngle) / 180.0;
    Color fillColor = _isTrackingLost ? const Color(0xFFEF4444).withValues(alpha: 0.35) : const Color(0xFF22C55E);
    
    String scoreText = _isTrackingLost ? "Paused — Last: ${_liveAngle.toStringAsFixed(0)}°" :
                       isLocked ? "${_liveAngle.toStringAsFixed(0)}° ✓ Locked" : 
                       "${_liveAngle.toStringAsFixed(0)}° / ${target.toStringAsFixed(0)}° target";

    return Container(
      color: const Color(0xFF002244),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("INSERTION ANGLE", style: TextStyle(color: Color(0xFFA8C4E0), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: fillColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                child: Text(scoreText, style: TextStyle(color: fillColor, fontSize: 11, fontWeight: FontWeight.bold)),
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
                child: Container(height: 8, decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(4))),
              ),
              Positioned(
                left: MediaQuery.of(context).size.width * (target / 180.0) - 20,
                top: -4,
                child: Container(width: 2, height: 16, color: const Color(0xFFA8C4E0)),
              )
            ],
          ),
          const SizedBox(height: 4),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0°', style: TextStyle(color: Colors.white38, fontSize: 9)),
              Text('45°', style: TextStyle(color: Colors.white38, fontSize: 9)),
              Text('90°', style: TextStyle(color: Colors.white38, fontSize: 9)),
              Text('135°', style: TextStyle(color: Colors.white38, fontSize: 9)),
              Text('180°', style: TextStyle(color: Colors.white38, fontSize: 9)),
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
          // If Tracking Lost Alert
          if (_isTrackingLost) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.pause_circle_outline, color: Color(0xFFEF4444)),
                  SizedBox(width: 10),
                  Expanded(child: Text("Angle recording is suspended until landmarks are re-acquired.", style: TextStyle(color: Color(0xFFB91C1C), fontSize: 11.5))),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Phase Tracker or Rubric Row depending on lock
          if (isLocked) 
            _buildPhaseTracker(session)
          else 
            _buildRubricRow(),

          const Divider(color: Color(0x11003366), height: 24),

          // Action Button
          _buildActionButton(session),
        ],
      ),
    );
  }

  Widget _buildRubricRow() {
    String title = _phase == DetectionPhase.insertion ? "Phase 1 — Insertion" : 
                   _phase == DetectionPhase.aspiration ? "Phase 2 — Aspiration" : "Phase 3 — Withdrawal";
    String desc = _phase == DetectionPhase.insertion ? "Awaiting needle insertion confirmation" : 
                  _phase == DetectionPhase.aspiration ? (_aspirationStarted ? "Aspirating..." : "Start aspiration motion") : "Awaiting withdrawal angle lock";
    
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: const Color(0xFFEFF7FF), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.colorize, color: Color(0xFF003366), size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF1A2E4A), fontSize: 12, fontWeight: FontWeight.bold)),
              Text(desc, style: const TextStyle(color: Color(0xFF4A6080), fontSize: 11)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFFEFF7FF), borderRadius: BorderRadius.circular(8)),
          child: const Text("In Progress", style: TextStyle(color: Color(0xFF003366), fontSize: 11, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }

  Widget _buildPhaseTracker(SessionStateProvider session) {
    // Score summary card
    int score = 0;
    String scoreDesc = "";
    if (_phase == DetectionPhase.insertion) {
      score = session.insertionScore ?? 0;
      scoreDesc = "Insertion Angle: ${(_lockedInsertionAngle ?? 0).toStringAsFixed(1)}° locked.";
    } else if (_phase == DetectionPhase.aspiration) {
      score = session.aspirationResult == 'Correct' ? 5 : session.aspirationResult == 'Incorrect' ? 2 : 1;
      scoreDesc = "Aspiration Result: ${session.aspirationResult}. Duration: ${_aspirationService.duration.toStringAsFixed(1)}s";
    } else {
      score = session.withdrawalScore ?? 0;
      scoreDesc = "Withdrawal Angle: ${(_lockedWithdrawalAngle ?? 0).toStringAsFixed(1)}° locked.";
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFDCFCE7), border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: const Color(0xFF22C55E).withValues(alpha: 0.15), border: Border.all(color: const Color(0xFF22C55E), width: 2.5), shape: BoxShape.circle),
                child: Center(child: Text(score.toString(), style: const TextStyle(color: Color(0xFF166534), fontSize: 20, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Score: $score / 5", style: const TextStyle(color: Color(0xFF166534), fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(scoreDesc, style: const TextStyle(color: Color(0xFF166534), fontSize: 12)),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildActionButton(SessionStateProvider session) {
    if (_isTrackingLost) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () => setState(() => _isTrackingLost = false),
          icon: const Icon(Icons.warning, color: Colors.white),
          label: const Text('Adjust Position & Resume', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF003366), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ),
      );
    }

    if (_phase == DetectionPhase.insertion) {
      if (_lockedInsertionAngle == null) {
        return _ActionButton(key: const Key('lock_insertion_button'), label: 'Confirm Needle Insertion', icon: Icons.check_circle_outline, onPressed: _angleInRange ? _lockInsertion : null);
      } else {
        return _ActionButton(key: const Key('proceed_aspiration_button'), label: 'Proceed to Aspiration Detection', icon: Icons.arrow_forward, onPressed: _proceedToAspiration);
      }
    } else if (_phase == DetectionPhase.aspiration) {
      if (!_aspirationStarted) {
        return _ActionButton(key: const Key('start_aspiration_button'), label: 'Start Aspiration', icon: Icons.play_arrow, onPressed: _startAspiration);
      } else if (!_aspirationLocked) {
        return _ActionButton(key: const Key('lock_aspiration_button'), label: 'Done Aspirating (${_aspirationService.duration.toStringAsFixed(1)}s)', icon: Icons.stop, onPressed: _aspirationService.duration >= 1.0 || _aspirationService.result == 'Not Detected' ? _lockAspiration : null);
      } else {
        return _ActionButton(key: const Key('proceed_withdrawal_button'), label: 'Proceed to Withdrawal', icon: Icons.arrow_forward, onPressed: _proceedToWithdrawal);
      }
    } else {
      if (!_withdrawalLocked) {
        return _ActionButton(key: const Key('lock_withdrawal_button'), label: 'Confirm Withdrawal Angle', icon: Icons.check_circle_outline, onPressed: _angleInRange ? _lockWithdrawal : null);
      } else {
        return _ActionButton(key: const Key('complete_session_button'), label: 'Complete Session', icon: Icons.flag, onPressed: _completeSession, color: const Color(0xFF22C55E));
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  const _ActionButton({super.key, required this.label, required this.icon, this.onPressed, this.color = const Color(0xFF003366)});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}


