import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/user_role_provider.dart';
import '../../services/roboflow_service.dart';
import '../../services/live_session_service.dart';
import '../../services/webrtc_signaling_service.dart';
import '../../widgets/detection_overlay_painter.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
const _greenBg    = Color(0xFFEEF9F3);
const _red        = Color(0xFF991B1B);
const _redBg      = Color(0xFFFEF2F2);
const _redBorder  = Color(0xFFFECACA);
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
  int    _liveScore = 0;
  String _currentPhase = 'waiting';
  Size? _imageSize;
  LiveSessionModel? _currentSession;

  Timer? _syncTimer;
  double? _lastInsertionAngle;
  String? _instructorId;

  // Roboflow detection state
  bool _detectionLost = false;
  RoboflowDetection? _latestDetection;

  // WebRTC P2P Mirroring
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final WebRtcSignalingService _signalingService = WebRtcSignalingService();
  StreamSubscription? _answerSub;
  StreamSubscription? _iceSub;
  StreamSubscription? _offerReqSub;
  dynamic _lastOfferRequestId;

  // Guide overlay
  bool _showGuide = false;

  // Withdrawal snapshot tracking
  Timer? _withdrawalTimer;
  bool _withdrawalSnapSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _instructorId = context.read<UserRoleProvider>().uid;
      
      if (_instructorId != null) {
        // Listen for offer requests from RemoteControlScreen (new session or retry)
        _offerReqSub = _signalingService.watchOfferRequest(_instructorId!).listen((reqId) {
          if (reqId != null && reqId != _lastOfferRequestId) {
            _lastOfferRequestId = reqId;
            debugPrint('[CameraNode WebRTC] 🔄 New offer request received ($reqId), negotiating...');
            _initWebRTC();
          }
        });
      }

      _initWebRTC(); // Initial offer generation

      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        _initCamera();
      });
    });
  }

  // Track processed SDP to prevent duplicate processing
  String? _lastAnswerSdp;
  bool _webrtcConnected = false;

  Future<void> _initWebRTC() async {
    final instructorId = _instructorId;
    if (instructorId == null) return;

    // Reset state and tear down old peer connection
    _lastAnswerSdp = null;
    _webrtcConnected = false;
    _answerSub?.cancel();
    _iceSub?.cancel();
    try {
      _dataChannel?.close();
      _peerConnection?.close();
    } catch (_) {}

    try {
      // Clear old signaling (non-fatal if it fails)
      await _signalingService.clearSignaling(instructorId);

      _peerConnection = await _signalingService.createConnection();

      // Setup ICE candidate listener to send to Firestore
      _peerConnection!.onIceCandidate = (candidate) {
        _signalingService.sendIceCandidate(instructorId, 'camera', candidate);
      };

      _peerConnection!.onIceConnectionState = (state) {
        debugPrint('[CameraNode WebRTC] ICE state: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _webrtcConnected = true;
        }
      };

      // Create Data Channel
      RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
        ..ordered = false // unordered is faster for video frames
        ..maxRetransmits = 0; // drop lost frames, don't retransmit
      _dataChannel = await _peerConnection!.createDataChannel('mirror', dataChannelDict);
      _dataChannel!.onDataChannelState = (state) {
        debugPrint('[CameraNode WebRTC] 📡 DataChannel state: $state');
      };

      // Create Offer
      final offer = await _peerConnection!.createOffer({});
      await _peerConnection!.setLocalDescription(offer);
      await _signalingService.sendOffer(instructorId, offer);

      // Listen for Answer — deduplicate and lock synchronously
      bool isProcessingAnswer = false;
      _answerSub = _signalingService.watchAnswer(instructorId).listen((answer) async {
        if (answer == null) return;
        if (_lastAnswerSdp == answer.sdp) return;
        if (isProcessingAnswer) return;
        if (_peerConnection == null) return;

        isProcessingAnswer = true;
        _lastAnswerSdp = answer.sdp; // Lock immediately to prevent duplicate runs

        try {
          final state = await _peerConnection!.getSignalingState();
          if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            await _peerConnection!.setRemoteDescription(answer);
            debugPrint('[CameraNode WebRTC] ✅ Answer applied');
          }
        } catch (e) {
          debugPrint('[CameraNode WebRTC] Error setting answer: $e');
        } finally {
          isProcessingAnswer = false;
        }
      });

      // Listen for Remote ICE candidates — track already-added candidates
      final Set<String> addedCandidates = {};
      _iceSub = _signalingService.watchIceCandidates(instructorId, 'remote').listen(
        (candidates) {
          for (var candidate in candidates) {
            final key = candidate.candidate ?? '';
            if (key.isNotEmpty && addedCandidates.add(key)) {
              _peerConnection!.addCandidate(candidate);
            }
          }
        },
        onError: (e) {
          debugPrint('[CameraNode WebRTC] ICE candidates stream error: $e');
        },
      );

      debugPrint('[CameraNode WebRTC] ✅ Initialization complete, offer published');
    } catch (e) {
      debugPrint('[CameraNode WebRTC] ❌ Init failed: $e');
    }
  }

  @override
  void dispose() {
    _offerReqSub?.cancel();
    _answerSub?.cancel();
    _iceSub?.cancel();
    _dataChannel?.close();
    _peerConnection?.close();
    
    _syncTimer?.cancel();
    _withdrawalTimer?.cancel();
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

  // ─── Dual Pipeline (Independent Mirroring & Inference) ─────────────────────
  int _lastMirrorTime = 0;
  bool _isMirroring = false;

  int _lastInferenceTime = 0;
  bool _isInferenceRunning = false;

  // Cache of the most recent raw frame — used for on-demand snapshot capture
  RawFrameData? _latestFrameData;


  void _onFrame(CameraImage image) {
    if (_currentPhase == 'completed') return;

    // Always update aspect ratio
    if (mounted && _imageSize == null) {
      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final needMirror = (now - _lastMirrorTime >= 33) &&
        !_isMirroring &&
        (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen);
    final needInference = (now - _lastInferenceTime >= 500) &&
        !_isInferenceRunning &&
        (_currentPhase != 'waiting' && _currentPhase != 'completed');

    if (!needMirror && !needInference) return;

    // Extract raw bytes synchronously so native CameraImage buffer is released immediately
    final isIOS = image.planes.length == 2;
    final frameData = RawFrameData(
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

    // Always cache latest frame for on-demand snapshot capture
    _latestFrameData = frameData;

    // 1. FAST MIRRORING PIPELINE (Immediate, 30 FPS, non-blocking pure video stream)
    if (needMirror) {
      _lastMirrorTime = now;
      _isMirroring = true;
      _processMirrorFrame(frameData);
    }

    // 2. AI INFERENCE PIPELINE (Parallel, 2 FPS)
    if (needInference) {
      _lastInferenceTime = now;
      _isInferenceRunning = true;
      _processInferenceFrame(frameData);
    }
  }

  Future<void> _processMirrorFrame(RawFrameData frameData) async {
    try {
      if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) return;
      if ((_dataChannel!.bufferedAmount ?? 0) > 32768) return; // Drop frame if SCTP buffer is busy

      final base64Frame = await RoboflowDetectionService.getFrameBase64(frameData);
      if (base64Frame != null && _dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        _dataChannel!.send(RTCDataChannelMessage(base64Frame));
      }
    } catch (e) {
      debugPrint('[CameraNode WebRTC] Error sending mirror frame: $e');
    } finally {
      _isMirroring = false;
    }
  }

  /// Captures a high-quality JPEG from the latest cached frame and sends it over
  /// the WebRTC DataChannel tagged as `SNAP:phase:base64`. The Remote Control
  /// screen stores this as the permanent feedback-module snapshot for that phase.
  Future<void> _sendSnapshot(String phase) async {
    final frameData = _latestFrameData;
    if (frameData == null) return;
    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) return;

    try {
      final base64Snap = await RoboflowDetectionService.getSnapshotBase64(frameData);
      if (base64Snap != null && _dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        _dataChannel!.send(RTCDataChannelMessage('SNAP:$phase:$base64Snap'));
        debugPrint('[CameraNode] 📸 Snapshot sent for phase: $phase');
      }
    } catch (e) {
      debugPrint('[CameraNode] Error sending snapshot: $e');
    }
  }

  Future<void> _processInferenceFrame(RawFrameData frameData) async {
    final instructorId = _instructorId;
    if (instructorId == null) {
      _isInferenceRunning = false;
      return;
    }

    try {
      final result = await RoboflowDetectionService.detectAngleFromFrameData(frameData);

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

      if (!result.detectionLost) {
        if (_currentPhase == 'insertion' || _currentPhase == 'withdrawal') {
          if (_liveAngle >= 0) {
            _liveService.updateLiveAngle(instructorId, _liveAngle);
          }
        }
      }
    } catch (e) {
      debugPrint('[CameraNode] Error in inference pipeline: $e');
    } finally {
      _isInferenceRunning = false;
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
      _withdrawalTimer?.cancel();
      _withdrawalSnapSent = false;
      setState(() {
        _lastInsertionAngle = null;
        _detectionLost = false;
        _latestDetection = null;
      });
      RoboflowDetectionService.resetSmoothing();
    } else if (session.phase == 'insertion_locked' && oldPhase == 'insertion') {
      final score = _scoreAngle(_liveAngle, session.targetAngle);
      _lastInsertionAngle = _liveAngle;
      _liveService.saveInsertionMetrics(instructorId, _liveAngle, score);
      // 📸 Capture insertion snapshot
      _sendSnapshot('insertion');
    } else if (session.phase == 'aspiration' && oldPhase == 'insertion_locked') {
      // 📸 Capture aspiration snapshot (beginning of aspiration phase)
      _sendSnapshot('aspiration');
    } else if (session.phase == 'withdrawal' && oldPhase != 'withdrawal') {
      RoboflowDetectionService.resetSmoothing();
      _withdrawalSnapSent = false;
      _withdrawalTimer?.cancel();
      // 📸 2-second delay snapshot after start of withdrawal phase
      _withdrawalTimer = Timer(const Duration(seconds: 2), () {
        if (_currentPhase == 'withdrawal' && !_withdrawalSnapSent) {
          _withdrawalSnapSent = true;
          _sendSnapshot('withdrawal');
        }
      });
    } else if (session.phase == 'withdrawal_locked' && oldPhase == 'withdrawal') {
      // If prematurely pressed confirm withdrawal before 2 seconds, auto capture immediately
      if (!_withdrawalSnapSent) {
        _withdrawalSnapSent = true;
        _withdrawalTimer?.cancel();
        _sendSnapshot('withdrawal');
      }
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
      backgroundColor: _bg,
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
              Container(color: _bg),
              if (!_cameraReady)
                Container(
                  color: _bg,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: _navy, strokeWidth: 3),
                        SizedBox(height: 24),
                        Text(
                          'PRISM',
                          style: TextStyle(color: _navy, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 6),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'INITIALIZING CAMERA...',
                          style: TextStyle(color: _textMid, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 2),
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

              // ── Detection Lost Overlay ──
              if (!isWaiting && _detectionLost)
                Positioned.fill(
                  child: Container(
                    color: _redBg.withValues(alpha: 0.75),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _redBorder, width: 2),
                          boxShadow: [BoxShadow(color: _red.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: _red, size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'DETECTION LOST',
                              style: TextStyle(color: _red, fontSize: 16,
                                  fontWeight: FontWeight.w900, letterSpacing: 1.5),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Syringe or arm not visible.\nReposition the camera.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _textDark,
                                  fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 20),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(() => _showGuide = true);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _bg,
                                  border: Border.all(color: _cardBorder),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.help_outline_rounded, color: _navy, size: 18),
                                    SizedBox(width: 8),
                                    Text('Show Placement Guide',
                                        style: TextStyle(color: _navy, fontSize: 13, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              if (isWaiting)
                Container(
                  color: Colors.white.withValues(alpha: 0.85),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _bg,
                            border: Border.all(color: _cardBorder, width: 2),
                          ),
                          child: const Icon(Icons.cast_connected, color: _navy, size: 36),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'CAMERA STANDBY',
                          style: TextStyle(color: _textDark, fontSize: 16,
                              fontWeight: FontWeight.w800, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Frame the patient. Waiting for remote start...',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _textMid, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 28),
                        GestureDetector(
                          onTap: () { HapticFeedback.lightImpact(); setState(() => _showGuide = true); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: _bg,
                              border: Border.all(color: _cardBorder),
                              borderRadius: BorderRadius.circular(12)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.help_outline_rounded, color: _navy, size: 18),
                              SizedBox(width: 8),
                              Text('Placement Guide', style: TextStyle(color: _navy, fontSize: 13, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: _navy,
                              borderRadius: BorderRadius.circular(12),
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
                  top: 48, left: 16, right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_formatName(session.studentName)} — ${session.injectionType} Injection',
                                style: const TextStyle(color: _textDark, fontSize: 16,
                                    fontWeight: FontWeight.w700, height: 1.2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 7, height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _navy,
                                      boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.25), blurRadius: 0, spreadRadius: 3)],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${session.phase.toUpperCase().replaceAll("_", " ")} PHASE ACTIVE',
                                    style: const TextStyle(color: _navyMid, fontSize: 11,
                                        fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _showGuide = !_showGuide);
                          },
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: _showGuide
                                  ? _accentBlue.withValues(alpha: 0.25)
                                  : _bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _showGuide ? _navy : _cardBorder),
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.help_outline_rounded,
                                color: _showGuide ? _navy : _textMid, size: 22),
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
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                      boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, -4))],
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
                                    fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _redBg,
                                border: Border.all(color: _redBorder),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('\u25cf REC',
                                  style: TextStyle(color: _red, fontSize: 10,
                                      fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildMetricCard('Phase',
                              session.phase.split('_')[0],
                              _navy),
                            const SizedBox(width: 8),
                            _buildMetricCard('Angle',
                              _detectionLost ? '---' : '${_liveAngle.toStringAsFixed(1)}°',
                              _detectionLost ? _textLight : _textDark),
                            const SizedBox(width: 8),
                            _buildMetricCard('Score',
                              _detectionLost ? '-' : '$_liveScore/5',
                              _liveScore >= 4 ? _green : _liveScore >= 2 ? const Color(0xFFB45309) : _red),
                          ],
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () {
                            _liveService.clearSession(instructorId);
                            Navigator.pop(context);
                          },
                          child: Container(
                            width: double.infinity, height: 48,
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
                                  '<svg width="15" height="15" viewBox="0 0 15 15" fill="none"><path d="M10 7.5H3M6 4.5L3 7.5L6 10.5" stroke="#4A5568" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 3h4v9H8" stroke="#4A5568" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                                ),
                                const SizedBox(width: 8),
                                const Text('Exit Camera Mode',
                                  style: TextStyle(color: _textMid,
                                      fontSize: 14, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_showGuide) _buildGuideOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGuideOverlay() {
    return GestureDetector(
      onTap: () => setState(() => _showGuide = false),
      child: Container(color: Colors.white.withValues(alpha: 0.90),
        child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => setState(() => _showGuide = false),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _bg,
                    border: Border.all(color: _cardBorder),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.close_rounded, color: _textDark, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PLACEMENT', style: TextStyle(color: _textDark, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.0)),
                  SizedBox(height: 3),
                  Text('HOW TO FRAME FOR BEST DETECTION', style: TextStyle(color: _navyMid, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                ],
              ),
              const Spacer(),
            ])),
          Expanded(child: Padding(padding: const EdgeInsets.all(20),
            child: Container(
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder, width: 1.5),
                boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/injection_placement_guide.jpg', fit: BoxFit.contain)))),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Column(children: [
            _InstructorGuideTip(icon: Icons.crop_free_rounded, color: _green, label: 'ARM',
              text: 'Keep the bare upper-arm / deltoid area centered — the GREEN box tracks this.'),
            const SizedBox(height: 10),
            _InstructorGuideTip(icon: Icons.vaccines_rounded, color: const Color(0xFF0284C7), label: 'SYRINGE',
              text: 'The entire syringe barrel must be visible from the side — the BLUE box tracks this.'),
            const SizedBox(height: 10),
            _InstructorGuideTip(icon: Icons.straighten_rounded, color: const Color(0xFFB45309), label: 'TRIPOD POSITION',
              text: 'Place the tripod level with the injection site, 30–50 cm away, facing the side of the arm.'),
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
            child: GestureDetector(onTap: () => setState(() => _showGuide = false),
              child: Container(height: 48, alignment: Alignment.center,
                decoration: BoxDecoration(color: _navy,
                  borderRadius: BorderRadius.circular(14)),
                child: const Text('Got it!', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))))),
        ]))),
    );
  }

  Widget _buildMetricCard(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _bg,
          border: Border.all(color: _cardBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
              style: const TextStyle(color: _textLight,
                  fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                style: TextStyle(color: valueColor, fontSize: 18,
                    fontWeight: FontWeight.w800, fontFamily: 'DM Mono')),
            ),
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

class _InstructorGuideTip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String text;
  const _InstructorGuideTip({
    required this.icon,
    required this.color,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: color, fontSize: 11,
                        fontWeight: FontWeight.w800, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(text,
                    style: const TextStyle(color: _textDark,
                        fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

