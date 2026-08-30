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

// --- Brand colours
const _accentBlue = Color(0xFFA8C4E0);
const _green      = Color(0xFF4ADE80);
const _greenDark  = Color(0xFF22C55E);
const _red        = Color(0xFFF87171);
const _amber      = Color(0xFFFCD34D);

class PracticeModeScreen extends StatefulWidget {
  const PracticeModeScreen({super.key});
  @override
  State<PracticeModeScreen> createState() => _PracticeModeScreenState();
}

class _PracticeModeScreenState extends State<PracticeModeScreen> {
  CameraController? _camera;
  bool _cameraReady = false;
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
    if (_availableCameras.length < 2) return;
    HapticFeedback.lightImpact();
    setState(() => _cameraReady = false);

    _currentCameraIndex = (_currentCameraIndex + 1) % _availableCameras.length;
    try {
      await _startCameraController(_availableCameras[_currentCameraIndex]);
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        Container(decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF001428), Color(0xFF001C38), Color(0xFF000E1E)]))),

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
                CameraPreview(_camera!),
                if (_latestDetection != null && !_detectionLost)
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

        // Top HUD Bar (Uniform with Instructor Node)
        if (_cameraReady)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.88),
              padding: const EdgeInsets.fromLTRB(18, 48, 18, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Practice Mode — IM Injection',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.2),
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
                              '${_practicePhase.toUpperCase()} PHASE ACTIVE',
                              style: const TextStyle(color: _accentBlue, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_availableCameras.length > 1) ...[
                        GestureDetector(
                          onTap: _toggleCamera,
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _showGuide = !_showGuide);
                        },
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: _showGuide ? _accentBlue.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: _showGuide ? Border.all(color: _accentBlue.withValues(alpha: 0.6)) : null,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.help_outline_rounded, color: _accentBlue, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Bottom Panel (Uniform with Instructor Node + Phase Progression)
        if (_cameraReady)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.90),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
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
                          color: const Color(0xFF1A7A4A).withValues(alpha: 0.25),
                          border: Border.all(color: const Color(0xFF1A7A4A).withValues(alpha: 0.5)),
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
                          Text('Exit Practice Mode',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Placement guide overlay
        if (_showGuide)
          GestureDetector(onTap: () => setState(() => _showGuide = false),
            child: Container(color: Colors.black.withValues(alpha: 0.92),
              child: SafeArea(child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(children: [
                    Container(width: 36, height: 36,
                      decoration: BoxDecoration(color: _accentBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10), border: Border.all(color: _accentBlue.withValues(alpha: 0.4))),
                      child: const Icon(Icons.camera_alt_outlined, color: _accentBlue, size: 18)),
                    const SizedBox(width: 12),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Placement Guide', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      Text('How to frame for best detection', style: TextStyle(color: _accentBlue, fontSize: 11)),
                    ]),
                    const Spacer(),
                    GestureDetector(onTap: () => setState(() => _showGuide = false),
                      child: Container(width: 32, height: 32,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 18))),
                  ])),
                Expanded(child: Padding(padding: const EdgeInsets.all(20),
                  child: ClipRRect(borderRadius: BorderRadius.circular(16),
                    child: Image.asset('assets/injection_placement_guide.jpg', fit: BoxFit.contain)))),
                Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Column(children: [
                  _GuideTip(icon: Icons.crop_free_rounded, color: _green, label: 'ARM',
                    text: 'Keep the bare upper-arm / deltoid area centered — the GREEN box tracks this.'),
                  const SizedBox(height: 10),
                  _GuideTip(icon: Icons.vaccines_rounded, color: const Color(0xFF22D3EE), label: 'SYRINGE',
                    text: 'The entire syringe barrel must be visible from the side — the CYAN box tracks this.'),
                  const SizedBox(height: 10),
                  _GuideTip(icon: Icons.straighten_rounded, color: _amber, label: 'CAMERA POSITION',
                    text: 'Level with the injection site, 30–50 cm away, looking straight at the side of the arm.'),
                ])),
                Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  child: GestureDetector(onTap: () => setState(() => _showGuide = false),
                    child: Container(height: 46, alignment: Alignment.center,
                      decoration: BoxDecoration(color: _accentBlue.withValues(alpha: 0.15),
                        border: Border.all(color: _accentBlue.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(14)),
                      child: const Text('Got it — Back to Camera', style: TextStyle(color: _accentBlue, fontSize: 14, fontWeight: FontWeight.w700))))),
              ])))),
      ]),
    );
  }

  Widget _buildPhaseContent() {
    // 3-Phase Angle Tracker Row (Angles only during live practice)
    Widget phaseTrackerRow() {
      final insText = _insertionAngle != null
          ? '${_insertionAngle!.toStringAsFixed(1)}°'
          : (_practicePhase == 'insertion' ? '${_liveAngle.toStringAsFixed(1)}°' : '—');
      final aspText = _practicePhase == 'insertion'
          ? '—'
          : (_practicePhase == 'aspiration' ? 'Checking' : 'No Blood');
      final wthText = _withdrawalAngle != null
          ? '${_withdrawalAngle!.toStringAsFixed(1)}°'
          : (_practicePhase == 'withdrawal' ? '${_liveAngle.toStringAsFixed(1)}°' : '—');

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _accentBlue.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Expanded(child: _buildPhaseLegendPill('1. Insertion', insText, _practicePhase == 'insertion')),
            Container(width: 1, height: 16, color: Colors.white.withValues(alpha: 0.12)),
            Expanded(child: _buildPhaseLegendPill('2. Aspiration', aspText, _practicePhase == 'aspiration')),
            Container(width: 1, height: 16, color: Colors.white.withValues(alpha: 0.12)),
            Expanded(child: _buildPhaseLegendPill('3. Withdrawal', wthText, _practicePhase == 'withdrawal')),
          ],
        ),
      );
    }

    if (_practicePhase == 'insertion') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          phaseTrackerRow(),
          Row(
            children: [
              _buildMetricCard('Phase', 'INSERTION', const Color(0xFFFCD34D)),
              const SizedBox(width: 8),
              _buildMetricCard('Live Angle',
                _detectionLost ? '---' : '${_liveAngle.toStringAsFixed(1)}°',
                _angleColor(_liveAngle)),
              const SizedBox(width: 8),
              _buildMetricCard('Target', '90.0° (±5°)', _accentBlue),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '💡 Align syringe perpendicular at 90° into the deltoid site.',
            style: TextStyle(color: _accentBlue, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      );
    } else if (_practicePhase == 'aspiration') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          phaseTrackerRow(),
          Row(
            children: [
              _buildMetricCard('Phase', 'ASPIRATION', const Color(0xFFFCD34D)),
              const SizedBox(width: 8),
              _buildMetricCard('Inserted Angle', '${_insertionAngle?.toStringAsFixed(1) ?? "90.0"}°', _accentBlue),
              const SizedBox(width: 8),
              _buildMetricCard('Blood Check', 'NO BLEEDING', _green),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '💡 Hold syringe steady at 90°. Aspirate gently for 5–10s to confirm no blood return.',
            style: TextStyle(color: _accentBlue, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          phaseTrackerRow(),
          Row(
            children: [
              _buildMetricCard('Phase', 'WITHDRAWAL', const Color(0xFFFCD34D)),
              const SizedBox(width: 8),
              _buildMetricCard('Live Angle',
                _detectionLost ? '---' : '${_liveAngle.toStringAsFixed(1)}°',
                _angleColor(_liveAngle)),
              const SizedBox(width: 8),
              _buildMetricCard('Delta',
                _detectionLost ? '---' : '${(_liveAngle - (_insertionAngle ?? 90)).abs().toStringAsFixed(1)}°',
                (_liveAngle - (_insertionAngle ?? 90)).abs() <= 5.0 ? _green : _amber),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '💡 Withdraw smoothly along the exact insertion path (maintain 90°).',
            style: TextStyle(color: _accentBlue, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      );
    }
  }

  Widget _buildPhaseLegendPill(String label, String value, bool isActive) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? _amber : (value != '—' ? _green : Colors.white.withValues(alpha: 0.3)),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: isActive ? _amber : (value != '—' ? _green : Colors.white.withValues(alpha: 0.4)),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseActionButton() {
    if (_isSaving) {
      return Container(
        width: double.infinity, height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFF16A34A),
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
            onTap: isBlocked ? null : _nextPhase,
            child: Container(
              width: double.infinity, height: 46,
              decoration: BoxDecoration(
                color: isBlocked ? Colors.grey : const Color(0xFF16A34A),
                borderRadius: BorderRadius.circular(14),
                boxShadow: isBlocked
                    ? null
                    : [BoxShadow(color: const Color(0xFF16A34A).withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
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
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _cancelPracticeWithBleeding,
            child: Container(
              width: double.infinity, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Cancel (Patient Bleeding)',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w700),
                  ),
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
      btnColor = isBlocked ? Colors.grey : const Color(0xFF004080);
      icon = Icons.arrow_forward_rounded;
    } else {
      label = isBlocked ? 'Detection Lost — Reposition Syringe' : 'Confirm Withdrawal & View Feedback';
      btnColor = isBlocked ? Colors.grey : const Color(0xFF16A34A);
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

  Widget _buildMetricCard(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: _accentBlue.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                style: TextStyle(color: valueColor, fontSize: 14,
                    fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            ),
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
        Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, height: 1.4)),
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
