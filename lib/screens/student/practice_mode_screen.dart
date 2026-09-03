import 'dart:async';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/session_model.dart';
import '../../services/feedback_service.dart';
import '../../services/instructor_session_repository.dart';
import '../../services/roboflow_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/detection_overlay_painter.dart';
import 'session_detail_screen.dart';

// ─── Brand Colours ─────────────────────────────────────────────────────────
const _navy       = Color(0xFF003366);
const _navyMid    = Color(0xFF004080);
const _navyDark   = Color(0xFF002244);
const _accentBlue = Color(0xFFA8C4E0);
const _bg         = Color(0xFFF8FAFC);
const _cardBg     = Color(0xFFFFFFFF);
const _cardBorder = Color(0xFFE2EAF4);
const _textDark   = Color(0xFF1A2B3C);
const _textMid    = Color(0xFF4A5568);
const _textLight  = Color(0xFF8A9BB0);
const _green      = Color(0xFF1A7A4A);
const _greenDark  = Color(0xFF22C55E);
const _greenBg    = Color(0xFFEEF9F3);
const _red        = Color(0xFF991B1B);
const _redBg      = Color(0xFFFEF2F2);
const _redBorder  = Color(0xFFFECACA);
const _amber      = Color(0xFFB45309);
// ──────────────────────────────────────────────────────────────────────────────

class PracticeModeScreen extends StatefulWidget {
  const PracticeModeScreen({super.key});
  @override
  State<PracticeModeScreen> createState() => _PracticeModeScreenState();
}

class _PracticeModeScreenState extends State<PracticeModeScreen> {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _isFlipping = false;
  List<CameraDescription> _availableCameras = [];
  int _currentCameraIndex = 0;

  double _liveAngle = 0;
  int    _liveScore = 0;
  bool   _detectionLost = false;
  RoboflowDetection? _latestDetection;

  bool _isInferenceRunning = false;
  int  _lastInferenceTime  = 0;
  bool _showGuide = false;

  // Snapshots for feedback module
  String? _insertionBase64;
  String? _aspirationBase64;
  String? _withdrawalBase64;
  RawFrameData? _lastFrameData;
  bool _isSaving = false;
  Timer? _withdrawalTimer;
  bool _withdrawalSnapSent = false;

  // Practice Phase State Machine: 'insertion' -> 'aspiration' -> 'withdrawal' -> 'completed'
  String _practicePhase = 'insertion';
  double? _insertionAngle;
  int?    _insertionScore;
  double? _withdrawalAngle;
  int?    _withdrawalScore;
  double? _delta;

  static const double _targetAngle = 90.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _withdrawalTimer?.cancel();
    _camera?.stopImageStream();
    _camera?.dispose();
    RoboflowDetectionService.resetSmoothing();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _availableCameras = cameras;

      // Default to FRONT camera for practice mode so student sees their own injection technique
      int frontIdx = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _currentCameraIndex = frontIdx != -1 ? frontIdx : 0;

      await _startCameraController(_availableCameras[_currentCameraIndex]);
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  Future<void> _startCameraController(CameraDescription description) async {
    if (_camera != null) {
      await _camera!.stopImageStream();
      await _camera!.dispose();
    }

    _camera = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _camera!.initialize();
    await _camera!.startImageStream(_onFrame);
    if (mounted) setState(() => _cameraReady = true);
  }

  Future<void> _toggleCamera() async {
    if (_availableCameras.length < 2 || _isFlipping) return;
    HapticFeedback.lightImpact();
    setState(() => _isFlipping = true);

    final currentDirection = _availableCameras[_currentCameraIndex].lensDirection;
    final nextIndex = _availableCameras.indexWhere((c) => c.lensDirection != currentDirection);
    
    if (nextIndex != -1) {
      _currentCameraIndex = nextIndex;
    } else {
      _currentCameraIndex = (_currentCameraIndex + 1) % _availableCameras.length;
    }

    try {
      await _startCameraController(_availableCameras[_currentCameraIndex]);
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    } finally {
      if (mounted) setState(() => _isFlipping = false);
    }
  }

  void _onFrame(CameraImage image) {
    if (_practicePhase == 'completed') return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - _lastInferenceTime < 500) || _isInferenceRunning) return;
    final isIOS = image.planes.length == 2;
    final frameData = RawFrameData(
      width:  image.width, height: image.height,
      yBytes: Uint8List.fromList(image.planes[0].bytes),
      uBytes: Uint8List.fromList(image.planes[1].bytes),
      vBytes: isIOS
          ? Uint8List.fromList(image.planes[1].bytes)
          : Uint8List.fromList(image.planes[2].bytes),
      yRowStride:   image.planes[0].bytesPerRow,
      uRowStride:   image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? (isIOS ? 2 : 1),
      sensorOrientation: _camera?.description.sensorOrientation ?? 270,
      isIOS: isIOS,
    );
    _lastFrameData = frameData;
    _lastInferenceTime = now;
    _isInferenceRunning = true;
    _runInference(frameData);
  }

  Future<void> _runInference(RawFrameData frameData) async {
    try {
      final result = await RoboflowDetectionService.detectAngleFromFrameData(frameData);
      if (!mounted) return;
      setState(() {
        _detectionLost   = result.detectionLost;
        _latestDetection = result.detection;
        if (!result.detectionLost) { _liveAngle = result.angle; _liveScore = result.score; }
      });
    } catch (_) {} finally { _isInferenceRunning = false; }
  }

  Color _angleColor(double a) {
    final d = (a - _targetAngle).abs();
    if (d <= 5)  return _green;
    if (d <= 15) return _amber;
    return _red;
  }

  void _nextPhase() async {
    HapticFeedback.lightImpact();
    
    if (_practicePhase == 'insertion') {
      _insertionAngle = _liveAngle;
      _insertionScore = _liveScore;
      if (_lastFrameData != null) {
        RoboflowDetectionService.getSnapshotBase64(_lastFrameData!).then((snap) {
          if (mounted && snap != null) _insertionBase64 = snap;
        });
      }
      setState(() => _practicePhase = 'aspiration');
    } else if (_practicePhase == 'aspiration') {
      if (_lastFrameData != null) {
        RoboflowDetectionService.getSnapshotBase64(_lastFrameData!).then((snap) {
          if (mounted && snap != null) _aspirationBase64 = snap;
        });
      }
      RoboflowDetectionService.resetSmoothing();
      _withdrawalSnapSent = false;
      _withdrawalTimer?.cancel();
      // 📸 2-second delay snapshot after start of withdrawal phase
      _withdrawalTimer = Timer(const Duration(seconds: 2), () async {
        if (_practicePhase == 'withdrawal' && !_withdrawalSnapSent && _lastFrameData != null) {
          _withdrawalSnapSent = true;
          final snap = await RoboflowDetectionService.getSnapshotBase64(_lastFrameData!);
          if (mounted && snap != null) _withdrawalBase64 = snap;
        }
      });
      setState(() => _practicePhase = 'withdrawal');
    } else if (_practicePhase == 'withdrawal') {
      _withdrawalAngle = _liveAngle;
      _withdrawalScore = _liveScore;
      _delta = (_liveAngle - (_insertionAngle ?? _targetAngle)).abs();
      
      // If prematurely confirmed withdrawal before 2 seconds, capture snapshot immediately
      _withdrawalTimer?.cancel();
      if (!_withdrawalSnapSent && _lastFrameData != null) {
        _withdrawalSnapSent = true;
        final snap = await RoboflowDetectionService.getSnapshotBase64(_lastFrameData!);
        if (mounted && snap != null) _withdrawalBase64 = snap;
      }
      await _saveAndCompletePractice();
    }
  }

  Future<void> _cancelPracticeWithBleeding() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';
      final name = user?.displayName ?? 'Student';

      final insAngle = _insertionAngle ?? _liveAngle;
      final insScore = _insertionScore ?? _liveScore;
      final wthAngle = _liveAngle;
      const wthScore = 1;
      final delta = (_liveAngle - insAngle).abs();
      final correspondence = delta <= 5.0 ? 'Matches' : 'Deviates';
      const aspirationResult = 'Bleeding Detected';
      const aspirationScore = 1;
      final overall = ((insScore + aspirationScore + wthScore) / 3).round();

      if (_lastFrameData != null) {
        final snap = await RoboflowDetectionService.getSnapshotBase64(_lastFrameData!);
        if (snap != null) _aspirationBase64 = snap;
      }

      final initialSession = SessionModel(
        sessionId: '',
        userId: email,
        studentName: name,
        timestamp: Timestamp.now(),
        injectionType: 'IM',
        sectionName: 'Practice',
        partnerName: 'Self-Practice',
        insertionAngle: insAngle,
        insertionScore: insScore,
        aspirationResult: aspirationResult,
        aspirationDuration: 2.0,
        motionSmoothness: 'Low',
        withdrawalAngle: wthAngle,
        withdrawalScore: wthScore,
        correspondenceResult: correspondence,
        angularDelta: delta,
        overallScore: overall,
        aiFeedbackText: '',
        feedbackStatus: 'Released',
        releaseTimestamp: Timestamp.now(),
        instructorNote: 'Vascular puncture observed during practice. Injection aborted.',
        flagged: true,
        insertionImageBase64: _insertionBase64,
        aspirationImageBase64: _aspirationBase64,
        withdrawalImageBase64: _withdrawalBase64,
      );

      final repo = InstructorSessionRepository();
      final docId = await repo.saveSession(initialSession);

      final sessionWithId = initialSession.copyWith(sessionId: docId);
      FeedbackService().generateAndSaveFeedbackInBackground(sessionWithId);

      if (user != null) {
        int practiceNum = 1;
        try {
          final countSnap = await FirebaseFirestore.instance
              .collection('sessions')
              .where('userId', isEqualTo: email)
              .where('sectionName', isEqualTo: 'Practice')
              .get();
          practiceNum = countSnap.docs.length;
        } catch (_) {}

        NotificationService().sendNotification(
          uid: user.uid,
          title: 'Practice Session #$practiceNum (Vascular Puncture)',
          body: 'IM Self-Practice #$practiceNum was aborted due to blood return detected during aspiration.',
          type: 'practice_completed',
          relatedSessionId: docId,
        );
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SessionDetailScreen(session: sessionWithId),
        ),
      );
    } catch (e) {
      debugPrint('Error saving bleeding practice session: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAndCompletePractice() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';
      final name = user?.displayName ?? 'Student';

      final insAngle = _insertionAngle ?? 90.0;
      final insScore = _insertionScore ?? 4;
      final wthAngle = _withdrawalAngle ?? 90.0;
      final wthScore = _withdrawalScore ?? 4;
      final delta = (_withdrawalAngle != null && _insertionAngle != null)
          ? (_withdrawalAngle! - _insertionAngle!).abs()
          : 0.0;
      final correspondence = delta <= 5.0 ? 'Matches' : 'Deviates';
      const aspirationResult = 'No Bleeding';
      const aspirationScore = 5;
      final overall = ((insScore + aspirationScore + wthScore) / 3).round();

      final initialSession = SessionModel(
        sessionId: '',
        userId: email,
        studentName: name,
        timestamp: Timestamp.now(),
        injectionType: 'IM',
        sectionName: 'Practice',
        partnerName: 'Self-Practice',
        insertionAngle: insAngle,
        insertionScore: insScore,
        aspirationResult: aspirationResult,
        aspirationDuration: 5.0,
        motionSmoothness: 'Good',
        withdrawalAngle: wthAngle,
        withdrawalScore: wthScore,
        correspondenceResult: correspondence,
        angularDelta: delta,
        overallScore: overall,
        aiFeedbackText: '',
        feedbackStatus: 'Released',
        releaseTimestamp: Timestamp.now(),
        instructorNote: '',
        flagged: false,
        insertionImageBase64: _insertionBase64,
        aspirationImageBase64: _aspirationBase64,
        withdrawalImageBase64: _withdrawalBase64,
      );

      final repo = InstructorSessionRepository();
      final docId = await repo.saveSession(initialSession);

      final sessionWithId = SessionModel(
        sessionId: docId,
        userId: email,
        studentName: name,
        timestamp: initialSession.timestamp,
        injectionType: 'IM',
        sectionName: 'Practice',
        partnerName: 'Self-Practice',
        insertionAngle: insAngle,
        insertionScore: insScore,
        aspirationResult: aspirationResult,
        aspirationDuration: 5.0,
        motionSmoothness: 'Good',
        withdrawalAngle: wthAngle,
        withdrawalScore: wthScore,
        correspondenceResult: correspondence,
        angularDelta: delta,
        overallScore: overall,
        aiFeedbackText: '',
        feedbackStatus: 'Released',
        releaseTimestamp: initialSession.releaseTimestamp,
        instructorNote: '',
        flagged: false,
        insertionImageBase64: _insertionBase64,
        aspirationImageBase64: _aspirationBase64,
        withdrawalImageBase64: _withdrawalBase64,
      );

      // Trigger background AI feedback generation
      FeedbackService().generateAndSaveFeedbackInBackground(sessionWithId);

      if (user != null) {
        int practiceNum = 1;
        try {
          final countSnap = await FirebaseFirestore.instance
              .collection('sessions')
              .where('userId', isEqualTo: email)
              .where('sectionName', isEqualTo: 'Practice')
              .get();
          practiceNum = countSnap.docs.length;
        } catch (_) {}

        NotificationService().sendNotification(
          uid: user.uid,
          title: 'Practice Session #$practiceNum Completed',
          body: 'Your IM self-practice #$practiceNum scored $overall/5. Clinical AI analysis is ready.',
          type: 'practice_completed',
          relatedSessionId: docId,
        );
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SessionDetailScreen(session: sessionWithId),
        ),
      );
    } catch (e) {
      debugPrint('Error saving practice session: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<Widget> _buildCornerGuides() {
    const color = _accentBlue;
    Widget corner(Alignment al) => Positioned.fill(
      child: Align(
        alignment: al,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(width: 28, height: 28,
            child: CustomPaint(painter: _CornerPainter(alignment: al, color: color, thickness: 3))),
        ),
      ),
    );
    return [corner(Alignment.topLeft), corner(Alignment.topRight),
            corner(Alignment.bottomLeft), corner(Alignment.bottomRight)];
  }

  Widget _buildSessionHeader() {
    return Container(
      color: _navy,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -30, top: -71,
            child: Container(
              width: 209, height: 207,
              decoration: BoxDecoration(color: _navyMid.withValues(alpha: 0.4), shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: -20, top: 28,
            child: Container(
              width: 153, height: 151,
              decoration: BoxDecoration(color: _navyDark.withValues(alpha: 0.3), shape: BoxShape.circle),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
            child: Column(
              children: [
                // Close + title row
                Row(
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
                          '<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M4 4l8 8M12 4l-8 8" stroke="rgba(255,255,255,0.7)" stroke-width="1.6" stroke-linecap="round"/></svg>',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.0)),
                          SizedBox(height: 3),
                          Text('STUDENT PRACTICE MODE', style: TextStyle(color: Color(0xFFA8C4E0), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                        ],
                      ),
                    ),
                    // Action Buttons
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _showGuide = !_showGuide);
                          },
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: _showGuide ? _accentBlue.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _showGuide ? _accentBlue.withValues(alpha: 0.6) : Colors.transparent),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.help_outline_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Injection type
                const Row(
                  children: [
                    Text(
                      'Intramuscular (IM) Injection',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Text(
                      'Target: 90\u00b0',
                      style: TextStyle(color: _accentBlue, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: const BoxDecoration(
        color: _cardBg,
        border: Border(bottom: BorderSide(color: _cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PhaseStep(label: 'Insertion',  state: _getPhaseState('insertion')),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('\u203a', style: TextStyle(color: _cardBorder, fontSize: 14))),
          _PhaseStep(label: 'Aspiration', state: _getPhaseState('aspiration')),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('\u203a', style: TextStyle(color: _cardBorder, fontSize: 14))),
          _PhaseStep(label: 'Withdrawal', state: _getPhaseState('withdrawal')),
        ],
      ),
    );
  }

  int _getPhaseState(String phaseName) {
    List<String> order = ['insertion', 'aspiration', 'withdrawal'];
    int targetIdx = order.indexOf(phaseName);
    int currentIdx = order.indexOf(_practicePhase);
    if (currentIdx > targetIdx) return 2; // completed
    if (currentIdx == targetIdx) return 1; // active
    return 0; // pending
  }

  Widget _buildFloatingMetricCard(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color ?? Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(fit: StackFit.expand, children: [
        Container(color: _bg),

        if (!_cameraReady)
          Container(color: const Color(0xFF003366), child: const Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              SizedBox(height: 24),
              Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 6)),
              SizedBox(height: 8),
              Text('INITIALIZING CAMERA...', style: TextStyle(color: _accentBlue, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 2)),
            ],
          ))),

        if (_cameraReady && _camera?.value.previewSize != null)
          SizedBox.expand(child: FittedBox(fit: BoxFit.cover,
            child: SizedBox(
              width: _camera!.value.previewSize!.height,
              height: _camera!.value.previewSize!.width,
              child: Stack(children: [
                if (_isFlipping)
                  Container(color: Colors.black)
                else
                  CameraPreview(_camera!),
                if (_latestDetection != null && !_detectionLost && !_isFlipping)
                  Positioned.fill(child: CustomPaint(painter: DetectionOverlayPainter(
                    detection: _latestDetection,
                    previewSize: Size(_camera!.value.previewSize!.height, _camera!.value.previewSize!.width),
                  ))),
              ]),
            ),
          )),

        ..._buildCornerGuides(),

        // Detection Lost overlay
        if (_cameraReady && _detectionLost)
          Positioned.fill(child: Container(color: Colors.red.withValues(alpha: 0.15),
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _red.withValues(alpha: 0.6), width: 2)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded, color: _red, size: 40),
                const SizedBox(height: 10),
                const Text('DETECTION LOST', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2)),
                const SizedBox(height: 6),
                Text('Syringe or arm not visible.\nReposition the camera.', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, height: 1.4)),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () { HapticFeedback.lightImpact(); setState(() => _showGuide = true); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: _accentBlue.withValues(alpha: 0.15),
                      border: Border.all(color: _accentBlue.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(10)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.help_outline_rounded, color: _accentBlue, size: 15),
                      SizedBox(width: 6),
                      Text('Show Placement Guide', style: TextStyle(color: _accentBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
            )),
          )),

        // Floating UI Layer
        if (_cameraReady)
          Column(
            children: [
              // Header
              Opacity(
                opacity: 0.95,
                child: _buildSessionHeader(),
              ),
              
              Opacity(
                opacity: 0.95,
                child: _buildPhaseBar(),
              ),

              // Floating Angle Data and Flip Camera
              Expanded(
                child: SafeArea(
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (_practicePhase == 'insertion') ...[
                                _buildFloatingMetricCard('Live Angle', _detectionLost ? '---' : '${_liveAngle.toStringAsFixed(1)}\u00b0'),
                                const SizedBox(height: 8),
                                _buildFloatingMetricCard('Target', '90.0\u00b0'),
                              ] else if (_practicePhase == 'aspiration') ...[
                                _buildFloatingMetricCard('Inserted Angle', '${_insertionAngle?.toStringAsFixed(1) ?? "90.0"}\u00b0', color: _accentBlue),
                                const SizedBox(height: 8),
                                _buildFloatingMetricCard('Blood Check', 'NO BLEEDING', color: _green),
                              ] else ...[
                                _buildFloatingMetricCard('Live Angle', _detectionLost ? '---' : '${_liveAngle.toStringAsFixed(1)}\u00b0',
                                  color: _angleColor(_liveAngle)),
                                const SizedBox(height: 8),
                                _buildFloatingMetricCard('Delta', _detectionLost ? '---' : '${(_liveAngle - (_insertionAngle ?? 90)).abs().toStringAsFixed(1)}\u00b0',
                                  color: (_liveAngle - (_insertionAngle ?? 90)).abs() <= 5.0 ? _green : _amber),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_availableCameras.length > 1)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16.0, bottom: 16.0),
                            child: GestureDetector(
                              onTap: _toggleCamera,
                              child: Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Controls Panel
              Container(
                decoration: const BoxDecoration(
                  color: _cardBg,
                  border: Border(top: BorderSide(color: _cardBorder)),
                  boxShadow: [BoxShadow(color: Color(0x12003366), blurRadius: 12, offset: Offset(0, -2))],
                ),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _greenBg,
                            border: Border.all(color: _green.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('PRACTICE',
                              style: TextStyle(color: _green, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _buildPhaseContent(),
                    const SizedBox(height: 12),

                    _buildPhaseActionButton(),
                    const SizedBox(height: 10),

                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity, height: 44,
                        decoration: BoxDecoration(
                          color: _bg,
                          border: Border.all(color: _cardBorder),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.string(
                              '<svg width="15" height="15" viewBox="0 0 15 15" fill="none"><path d="M10 7.5H3M6 4.5L3 7.5L6 10.5" stroke="#8A9BB0" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 3h4v9H8" stroke="#8A9BB0" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                            ),
                            const SizedBox(width: 7),
                            const Text('Exit Practice Mode',
                              style: TextStyle(color: _textMid, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

        // Placement guide overlay
        if (_showGuide)
          GestureDetector(onTap: () => setState(() => _showGuide = false),
            child: Container(color: Colors.black.withValues(alpha: 0.65),
              child: SafeArea(child: Column(children: [
                Expanded(child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Column(
                    children: [
                      Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Row(children: [
                          Container(width: 36, height: 36,
                            decoration: BoxDecoration(color: _bg,
                              borderRadius: BorderRadius.circular(10), border: Border.all(color: _cardBorder)),
                            child: const Icon(Icons.camera_alt_outlined, color: _navy, size: 18)),
                          const SizedBox(width: 12),
                          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Placement Guide', style: TextStyle(color: _textDark, fontSize: 16, fontWeight: FontWeight.w800)),
                            Text('How to frame for best detection', style: TextStyle(color: _textMid, fontSize: 11)),
                          ]),
                          const Spacer(),
                          GestureDetector(onTap: () => setState(() => _showGuide = false),
                            child: Container(width: 32, height: 32,
                              decoration: BoxDecoration(color: _bg, border: Border.all(color: _cardBorder), borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.close_rounded, color: _navy, size: 18))),
                        ])),
                      Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ClipRRect(borderRadius: BorderRadius.circular(12),
                          child: Container(
                            color: _bg,
                            child: Image.asset('assets/injection_placement_guide.jpg', fit: BoxFit.contain),
                          )))),
                      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 12), child: Column(children: [
                        _GuideTip(icon: Icons.crop_free_rounded, color: _green, label: 'ARM',
                          text: 'Keep the bare upper-arm / deltoid area centered — the GREEN box tracks this.'),
                        const SizedBox(height: 10),
                        _GuideTip(icon: Icons.vaccines_rounded, color: const Color(0xFF0284C7), label: 'SYRINGE',
                          text: 'The entire syringe barrel must be visible from the side — the BLUE box tracks this.'),
                        const SizedBox(height: 10),
                        _GuideTip(icon: Icons.straighten_rounded, color: _amber, label: 'CAMERA POSITION',
                          text: 'Level with the injection site, 30–50 cm away, looking straight at the side of the arm.'),
                      ])),
                      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: GestureDetector(onTap: () => setState(() => _showGuide = false),
                          child: Container(height: 46, alignment: Alignment.center,
                            decoration: BoxDecoration(color: _bg,
                              border: Border.all(color: _cardBorder),
                              borderRadius: BorderRadius.circular(14)),
                            child: const Text('Got it!', style: TextStyle(color: _navy, fontSize: 14, fontWeight: FontWeight.w700))))),
                    ],
                  ),
                )),
              ])))),
      ]),
    );
  }

  Widget _buildPhaseContent() {
    // 3-Phase Angle Tracker Row (Angles only during live practice)
    if (_practicePhase == 'insertion') {
      return const Text(
        'Align syringe perpendicular at 90° into the deltoid site.',
        style: TextStyle(color: _textMid, fontSize: 11, fontWeight: FontWeight.w500),
      );
    } else if (_practicePhase == 'aspiration') {
      return const Text(
        'Hold syringe steady at 90°. Aspirate gently for 5–10s to confirm no blood return.',
        style: TextStyle(color: _textMid, fontSize: 11, fontWeight: FontWeight.w500),
      );
    } else {
      return const Text(
        'Withdraw smoothly along the exact insertion path (maintain 90°).',
        style: TextStyle(color: _textMid, fontSize: 11, fontWeight: FontWeight.w500),
      );
    }
  }

  Widget _buildPhaseActionButton() {
    if (_isSaving) {
      return Container(
        width: double.infinity, height: 46,
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Saving & Launching Feedback...', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final isBlocked = _detectionLost;

    if (_practicePhase == 'aspiration') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _cancelPracticeWithBleeding,
            child: Container(
              width: double.infinity, height: 44,
              decoration: BoxDecoration(
                color: _redBg,
                border: Border.all(color: _redBorder),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, color: _red, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Cancel (Patient Bleeding)',
                    style: TextStyle(color: _red, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: isBlocked ? null : _nextPhase,
            child: Container(
              width: double.infinity, height: 46,
              decoration: BoxDecoration(
                color: isBlocked ? _textLight : _green,
                borderRadius: BorderRadius.circular(14),
                boxShadow: isBlocked
                    ? null
                    : [BoxShadow(color: _green.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      isBlocked ? 'Detection Lost — Reposition Syringe' : 'No Bleeding (Proceed to Withdrawal)',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ],
      );
    }

    String label;
    Color btnColor;
    IconData icon;

    if (_practicePhase == 'insertion') {
      label = isBlocked ? 'Detection Lost — Reposition Syringe' : 'Lock Angle & Proceed to Aspiration';
      btnColor = isBlocked ? _textLight : _navy;
      icon = Icons.arrow_forward_rounded;
    } else {
      label = isBlocked ? 'Detection Lost — Reposition Syringe' : 'Confirm Withdrawal & View Feedback';
      btnColor = isBlocked ? _textLight : _green;
      icon = Icons.check_circle_outline_rounded;
    }

    return GestureDetector(
      onTap: isBlocked ? null : _nextPhase,
      child: Container(
        width: double.infinity, height: 46,
        decoration: BoxDecoration(
          color: btnColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isBlocked
              ? null
              : [BoxShadow(color: btnColor.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

}

// Guide tip row
class _GuideTip extends StatelessWidget {
  final IconData icon; final Color color; final String label, text;
  const _GuideTip({required this.icon, required this.color, required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 32, height: 32,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Icon(icon, color: color, size: 16)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(text, style: const TextStyle(color: _textMid, fontSize: 12, height: 1.4)),
      ])),
    ]);
  }
}

// Corner painter
class _CornerPainter extends CustomPainter {
  final Alignment alignment; final Color color; final double thickness;
  const _CornerPainter({required this.alignment, required this.color, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.7)..strokeWidth = thickness
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final isTop  = alignment == Alignment.topLeft || alignment == Alignment.topRight;
    final isLeft = alignment == Alignment.topLeft || alignment == Alignment.bottomLeft;
    final x = isLeft ? 0.0 : size.width; final y = isTop ? 0.0 : size.height;
    final dx = isLeft ? size.width : -size.width; final dy = isTop ? size.height : -size.height;
    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) => old.color != color;
}

// ── Phase Step ────────────────────────────────────────────────────────────────
class _PhaseStep extends StatelessWidget {
  final String label;
  final int    state; // 0=pending, 1=active, 2=completed
  const _PhaseStep({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    late Color color;
    if (state == 2) color = const Color(0xFF1A7A4A);
    else if (state == 1) color = _navy;
    else color = _textMid;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
