import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../providers/user_role_provider.dart';
import '../../services/live_session_service.dart';
import '../../services/instructor_session_repository.dart';
import '../../models/session_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/feedback_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/webrtc_signaling_service.dart';

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
const _greenBorder = Color(0xFFA8D5B8);
const _amber      = Color(0xFFB45309);
// ──────────────────────────────────────────────────────────────────────────────

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final _liveService = LiveSessionService();
  final _repo = InstructorSessionRepository();
  final _feedbackService = FeedbackService();

  // WebRTC
  RTCPeerConnection? _peerConnection;
  final WebRtcSignalingService _signalingService = WebRtcSignalingService();
  StreamSubscription? _offerSub;
  StreamSubscription? _iceSub;
  String? _webrtcFrameBase64;
  String? _instructorId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _instructorId = context.read<UserRoleProvider>().uid;
      _initWebRTC();
    });
  }

  Future<void> _initWebRTC() async {
    final instructorId = _instructorId;
    if (instructorId == null) return;

    _peerConnection = await _signalingService.createConnection();

    // Listen for data channel from the camera node
    _peerConnection!.onDataChannel = (channel) {
      channel.onMessage = (RTCDataChannelMessage message) {
        if (message.type == MessageType.text) {
          if (mounted) {
            setState(() {
              _webrtcFrameBase64 = message.text;
            });
          }
        }
      };
    };

    // Setup ICE candidate listener to send to Firestore
    _peerConnection!.onIceCandidate = (candidate) {
      _signalingService.sendIceCandidate(instructorId, 'remote', candidate);
    };

    // Listen for Offer
    _offerSub = _signalingService.watchOffer(instructorId).listen((offer) async {
      if (offer != null) {
        final state = await _peerConnection!.getSignalingState();
        if (state != RTCSignalingState.RTCSignalingStateStable) {
          await _peerConnection!.setRemoteDescription(offer);
          final answer = await _peerConnection!.createAnswer({});
          await _peerConnection!.setLocalDescription(answer);
          await _signalingService.sendAnswer(instructorId, answer);
        }
      }
    });

    // Listen for Remote ICE candidates
    _iceSub = _signalingService.watchIceCandidates(instructorId, 'camera').listen((candidates) {
      for (var candidate in candidates) {
        _peerConnection!.addCandidate(candidate);
      }
    });
  }

  @override
  void dispose() {
    _offerSub?.cancel();
    _iceSub?.cancel();
    _peerConnection?.close();
    super.dispose();
  }

  void _updatePhase(String instructorId, String newPhase) {
    _liveService.updatePhase(instructorId, newPhase);
  }

  void _completeSession(String instructorId, LiveSessionModel session) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    String finalUserId = session.studentEmail;

    // Build final session model
    // Aspiration is skipped — hardcode values
    const aspirationResult = 'Skipped';

    // Overall score: average of insertion + withdrawal only
    final overallScore = (((session.insertionScore ?? 1) + (session.withdrawalScore ?? 1)) / 2).round();

    // Build final session model with empty feedback
    SessionModel initialSession = SessionModel(
      sessionId: '', // Auto-generated
      userId: finalUserId, 
      studentName: session.studentName,
      timestamp: Timestamp.now(), 
      injectionType: session.injectionType,
      sectionName: session.sectionName,
      partnerName: session.partnerName,
      insertionAngle: session.finalInsertionAngle ?? 0,
      insertionScore: session.insertionScore ?? 1,
      aspirationResult: aspirationResult,
      aspirationDuration: 0,
      motionSmoothness: 'N/A',
      withdrawalAngle: session.finalWithdrawalAngle ?? 0,
      withdrawalScore: session.withdrawalScore ?? 1,
      correspondenceResult: session.correspondenceResult ?? 'Deviates',
      angularDelta: session.angularDelta ?? 0,
      overallScore: overallScore,
      aiFeedbackText: '',
      feedbackStatus: 'Pending',
      instructorNote: '',
      flagged: false,
    );

    // Save immediately and get ID
    final generatedSessionId = await _repo.saveSession(initialSession);
    
    // Reconstruct with ID for background task
    SessionModel sessionWithId = SessionModel(
      sessionId: generatedSessionId,
      userId: finalUserId, 
      studentName: session.studentName,
      timestamp: initialSession.timestamp, 
      injectionType: session.injectionType,
      sectionName: session.sectionName,
      partnerName: session.partnerName,
      insertionAngle: session.finalInsertionAngle ?? 0,
      insertionScore: session.insertionScore ?? 1,
      aspirationResult: aspirationResult,
      aspirationDuration: 0,
      motionSmoothness: 'N/A',
      withdrawalAngle: session.finalWithdrawalAngle ?? 0,
      withdrawalScore: session.withdrawalScore ?? 1,
      correspondenceResult: session.correspondenceResult ?? 'Deviates',
      angularDelta: session.angularDelta ?? 0,
      overallScore: overallScore,
      aiFeedbackText: '',
      feedbackStatus: 'Pending',
      instructorNote: '',
      flagged: false,
    );

    // Fire and forget background generation
    _feedbackService.generateAndSaveFeedbackInBackground(sessionWithId);

    if (mounted) {
      Navigator.pop(context); // Close loading dialog
      _liveService.clearSession(instructorId);
      Navigator.pop(context); // Close screen
    }
  }

  void _cancelSessionWithBleeding(String instructorId, LiveSessionModel session) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    String finalUserId = session.studentEmail;

    SessionModel failedSession = SessionModel(
      sessionId: '', // Auto-generated
      userId: finalUserId, 
      studentName: session.studentName,
      timestamp: Timestamp.now(), 
      injectionType: session.injectionType,
      sectionName: session.sectionName,
      partnerName: session.partnerName,
      insertionAngle: session.finalInsertionAngle ?? 0,
      insertionScore: 1, // failed
      aspirationResult: 'Failed (Bleeding)',
      aspirationDuration: 0,
      motionSmoothness: 'N/A',
      withdrawalAngle: 0,
      withdrawalScore: 1,
      correspondenceResult: 'Deviates',
      angularDelta: 0,
      overallScore: 1, // Automatic fail
      aiFeedbackText: 'Session automatically failed due to bleeding during aspiration.',
      feedbackStatus: 'Failed',
      instructorNote: 'Instructor triggered cancellation due to bleeding.',
      flagged: true,
    );

    await _repo.saveSession(failedSession);
    
    if (mounted) {
      Navigator.pop(context); // Close dialog
      _liveService.clearSession(instructorId);
      Navigator.pop(context); // Close screen
    }
  }

  @override
  Widget build(BuildContext context) {
    final instructorId = context.watch<UserRoleProvider>().uid;

    return Scaffold(
      backgroundColor: _cardBg,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<LiveSessionModel?>(
          stream: _liveService.watchSession(instructorId!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _navy));
            }

            final session = snapshot.data;
            if (session == null) {
              return Column(
                children: [
                  _buildAppBar(instructorId),
                  const Expanded(
                    child: Center(
                      child: Text('Session ended or not found.', style: TextStyle(color: _textMid)),
                    ),
                  ),
                ],
              );
            }

            return Stack(
              children: [
                // Camera Mirror Feed
                if (_webrtcFrameBase64 != null && _webrtcFrameBase64!.isNotEmpty)
                  Positioned.fill(
                    child: Image.memory(
                      base64Decode(_webrtcFrameBase64!),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  )
                else
                  Positioned.fill(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: _accentBlue),
                          const SizedBox(height: 16),
                          const Text('Waiting for camera feed...', style: TextStyle(color: _accentBlue)),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry Connection'),
                            onPressed: () {
                              _initWebRTC();
                            },
                          )
                        ],
                      ),
                    ),
                  ),

                // Floating UI Layer
                Column(
                  children: [
                    // Header (semi-transparent)
                    Opacity(
                      opacity: 0.85,
                      child: _buildSessionHeader(instructorId, session),
                    ),
                    
                    Opacity(
                      opacity: 0.85,
                      child: _buildPhaseBar(session),
                    ),

                    // Floating Angle Data
                    Expanded(
                      child: SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Live Angle: ${session.liveAngle.toStringAsFixed(0)}\u00b0',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Target: ${session.targetAngle.toStringAsFixed(0)}\u00b0',
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),


                // ── Controls panel ─────────────────────────────────────────
                    _buildControls(instructorId, session),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSessionHeader(String instructorId, LiveSessionModel session) {
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                // Close + title row
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        _liveService.clearSession(instructorId);
                        Navigator.pop(context);
                      },
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.0)),
                        SizedBox(height: 3),
                        Text('LIVE DEMO CONTROL', style: TextStyle(color: Color(0xFFA8C4E0), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Student block
                Text(session.studentName,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${session.injectionType} Injection \u00b7 Target: ${session.targetAngle.toStringAsFixed(0)}\u00b0',
                  style: const TextStyle(color: _accentBlue, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              // UI design from origin/main keeps it empty here.
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(String instructorId) {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    _liveService.clearSession(instructorId);
                    Navigator.pop(context);
                  },
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
                const Text('Live Demo Control',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseBar(LiveSessionModel session) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: const BoxDecoration(
        color: _cardBg,
        border: Border(bottom: BorderSide(color: _cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PhaseStep(label: 'Insertion',  state: _getPhaseState(session.phase, 1)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('\u203a', style: TextStyle(color: _cardBorder, fontSize: 14))),
          _PhaseStep(label: 'Withdrawal', state: _getPhaseState(session.phase, 2)),
        ],
      ),
    );
  }

  Widget _buildControls(String instructorId, LiveSessionModel session) {
    return Container(
      decoration: const BoxDecoration(
        color: _cardBg,
        border: Border(top: BorderSide(color: _cardBorder)),
        boxShadow: [BoxShadow(color: Color(0x12003366), blurRadius: 12, offset: Offset(0, -2))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: Column(
        children: [
          const Text('PHASE CONTROL',
            style: TextStyle(color: _textMid, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.12 * 10)),
          const SizedBox(height: 12),
          _buildControlButton(instructorId, session),
        ],
      ),
    );
  }

  Widget _buildControlButton(String instructorId, LiveSessionModel session) {
    if (session.phase == 'waiting') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            label: 'Start Insertion Phase',
            hint: 'Tap to begin tracking',
            color: _navy,
            onPressed: () => _updatePhase(instructorId, 'insertion'),
          ),
        ],
      );
    } 

    if (session.phase == 'withdrawal_locked') {
      return _ControlButton(
        label: 'Complete & Save Session',
        hint: 'Tap to finalize and generate feedback',
        color: const Color(0xFF16A34A),
        onPressed: () => _completeSession(instructorId, session),
      );
    }

    // Common Guardrails for active tracking phases
    final bool guardrailBlocked = session.detectionLost;
    
    Widget button;
    if (session.phase == 'insertion') {
      button = _ControlButton(
        label: 'Confirm Needle Insertion',
        hint: 'Tap when the needle is fully inserted',
        color: const Color(0xFF92400E),
        onPressed: guardrailBlocked ? () {} : () => _updatePhase(instructorId, 'insertion_locked'),
      );
    } else if (session.phase == 'insertion_locked') {
      button = _ControlButton(
        label: 'Proceed to Aspiration',
        hint: 'Tap to continue to aspiration phase',
        color: _navy,
        onPressed: () => _updatePhase(instructorId, 'aspiration'),
      );
    } else if (session.phase == 'aspiration') {
      button = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            label: 'No Bleeding (Proceed to Withdrawal)',
            hint: 'Aspiration clear',
            color: const Color(0xFF16A34A),
            onPressed: () => _updatePhase(instructorId, 'withdrawal'),
          ),
          const SizedBox(height: 12),
          _ControlButton(
            label: 'Cancel (Patient Bleeding)',
            hint: 'Fails session immediately',
            color: Colors.redAccent,
            onPressed: () => _cancelSessionWithBleeding(instructorId, session),
          ),
        ]
      );
    } else if (session.phase == 'withdrawal') {
      button = _ControlButton(
        label: 'Confirm Needle Withdrawal',
        hint: 'Tap when the needle is fully withdrawn',
        color: const Color(0xFF92400E),
        onPressed: guardrailBlocked ? () {} : () => _updatePhase(instructorId, 'withdrawal_locked'),
      );
    } else {
      button = const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (guardrailBlocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Detection lost. Reposition hand.', 
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)
                ),
              ],
            ),
          ),
        button,
      ],
    );
  }

  // 0: inactive, 1: active, 2: done
  int _getPhaseState(String currentPhase, int step) {
    if (step == 1) {
      if (currentPhase == 'waiting' || currentPhase == 'insertion') return 1;
      return 2;
    } else {
      // Step 2 = Withdrawal
      if (currentPhase == 'insertion_locked' || currentPhase == 'aspiration' || currentPhase == 'withdrawal') return 1;
      if (currentPhase == 'withdrawal_locked') return 2;
      return 0;
    }
  }
}

// ── Phase Step ────────────────────────────────────────────────────────────────
class _PhaseStep extends StatelessWidget {
  final String label;
  final int state; // 0 inactive, 1 active, 2 done
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

// ── Gauge ─────────────────────────────────────────────────────────────────────
class _Gauge extends StatelessWidget {
  final double angle;
  const _Gauge({required this.angle});

  @override
  Widget build(BuildContext context) {
    final fill = (angle.clamp(0, 180) / 180).clamp(0.0, 1.0);
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 7,
              decoration: BoxDecoration(color: _cardBorder, borderRadius: BorderRadius.circular(4)),
              child: FractionallySizedBox(
                widthFactor: fill,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: _navy,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Positioned(
              left: (MediaQuery.of(context).size.width - 40 - 32) * fill - 7,
              top: -3.5,
              child: Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: _cardBg,
                  border: Border.all(color: _navy, width: 2.5),
                  boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 1))],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0\u00b0',   style: TextStyle(color: _textMid, fontSize: 10, fontWeight: FontWeight.w500)),
            Text('45\u00b0',  style: TextStyle(color: _textMid, fontSize: 10, fontWeight: FontWeight.w500)),
            Text('90\u00b0',  style: TextStyle(color: _textMid, fontSize: 10, fontWeight: FontWeight.w500)),
            Text('135\u00b0', style: TextStyle(color: _textMid, fontSize: 10, fontWeight: FontWeight.w500)),
            Text('180\u00b0', style: TextStyle(color: _textMid, fontSize: 10, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}

// ── Metric Row ────────────────────────────────────────────────────────────────
class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color  valueColor;
  const _MetricRow({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: _textMid, fontSize: 12)),
      Text(value,  style: TextStyle(color: valueColor, fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'DM Mono')),
    ],
  );
}

// ── Pill ──────────────────────────────────────────────────────────────────────
Widget _pill(String label, {required Color bg, required Color border, required Color text}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(label, style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.w600)),
    );

// ── Control Button ────────────────────────────────────────────────────────────
class _ControlButton extends StatelessWidget {
  final String label;
  final Color  color;
  final String hint;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.label,
    required this.color,
    required this.hint,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: double.infinity, height: 58,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            alignment: Alignment.center,
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 8),
        Text(hint, style: const TextStyle(color: _textMid, fontSize: 11.5), textAlign: TextAlign.center),
      ],
    );
  }
}
