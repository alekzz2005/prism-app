import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../providers/user_role_provider.dart';
import '../../services/live_session_service.dart';
import '../../services/instructor_session_repository.dart';
import '../../models/session_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/feedback_service.dart';

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

  DateTime? _aspirationStartTime;

  void _updatePhase(String instructorId, String newPhase) {
    if (newPhase == 'aspiration') {
      _aspirationStartTime = DateTime.now();
      _liveService.updatePhase(instructorId, newPhase);
    } else if (newPhase == 'aspiration_locked') {
      _liveService.updatePhase(instructorId, newPhase);
      if (_aspirationStartTime != null) {
        final duration = DateTime.now().difference(_aspirationStartTime!).inMilliseconds / 1000.0;
        _liveService.saveAspirationMetrics(instructorId, 'Correct', duration, 'N/A');
      }
    } else {
      _liveService.updatePhase(instructorId, newPhase);
    }
  }

  void _completeSession(String instructorId, LiveSessionModel session) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    String finalUserId = session.studentEmail.toLowerCase();

    // Build final session model
    // For ID injections, aspiration is N/A per the rubric
    final isID = session.injectionType == 'ID';
    final aspirationResult = isID ? 'N/A' : (session.aspirationResult ?? 'Not Detected');
    final aspirationScore = isID ? 0 : ((aspirationResult == 'Correct') ? 5 : 1);

    // ID averages 2 components (insertion + withdrawal), others average 3 (+ aspiration)
    final overallScore = isID
        ? (((session.insertionScore ?? 1) + (session.withdrawalScore ?? 1)) / 2).round()
        : (((session.insertionScore ?? 1) + (session.withdrawalScore ?? 1) + aspirationScore) / 3).round();

    // Build final session model with empty feedback
    SessionModel initialSession = SessionModel(
      sessionId: '', // Auto-generated
      userId: finalUserId, 
      studentName: session.studentName,
      timestamp: Timestamp.now(), 
      injectionType: session.injectionType,
      sectionName: session.sectionName,
      insertionAngle: session.finalInsertionAngle ?? 0,
      insertionScore: session.insertionScore ?? 1,
      aspirationResult: aspirationResult,
      aspirationDuration: isID ? 0 : (session.aspirationDuration ?? 0),
      motionSmoothness: isID ? 'N/A' : (session.motionSmoothness ?? 'Low'),
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
      insertionAngle: session.finalInsertionAngle ?? 0,
      insertionScore: session.insertionScore ?? 1,
      aspirationResult: aspirationResult,
      aspirationDuration: isID ? 0 : (session.aspirationDuration ?? 0),
      motionSmoothness: isID ? 'N/A' : (session.motionSmoothness ?? 'Low'),
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

    if (!mounted) return;
    Navigator.pop(context); // Pop the loading dialog
    Navigator.pop(context); // Go back to dashboard instantly
    
    // Clear live session AFTER popping animation finishes to avoid jitter
    Future.delayed(const Duration(milliseconds: 400), () {
      _liveService.clearSession(instructorId);
    });
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

            return Column(
              children: [
                // ── Navy header with student info ──────────────────────────
                _buildSessionHeader(instructorId, session),

                // ── Phase bar ─────────────────────────────────────────────
                _buildPhaseBar(session),

                // ── Live angle + gauge + metrics ───────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: Column(
                      children: [
                        const Text('LIVE INSERTION ANGLE',
                          style: TextStyle(color: _textMid, fontSize: 11,
                              fontWeight: FontWeight.w700, letterSpacing: 0.15 * 10)),

                        const SizedBox(height: 18),

                        // Angle ring
                        SizedBox(
                          width: 180, height: 180,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CircularProgressIndicator(
                                value: (session.liveAngle.clamp(0, 180) / 180).clamp(0.0, 1.0),
                                backgroundColor: _navy.withValues(alpha: 0.08),
                                color: _navy,
                                strokeWidth: 8,
                                strokeCap: StrokeCap.round,
                              ),
                              Center(
                                child: Container(
                                  width: 150, height: 150,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _navy.withValues(alpha: 0.04)),
                                    color: _cardBg,
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        session.liveAngle.toStringAsFixed(0),
                                        style: const TextStyle(color: _navy, fontSize: 58,
                                            fontWeight: FontWeight.w700, fontFamily: 'DM Mono', height: 1),
                                      ),
                                      const Text('\u00b0',
                                        style: TextStyle(color: _textMid, fontSize: 22,
                                            fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Pills
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _pill(
                              'Target: ${session.targetAngle.toStringAsFixed(0)}\u00b0',
                              bg: _navy.withValues(alpha: 0.07),
                              border: _cardBorder,
                              text: _navy,
                            ),
                            const SizedBox(width: 8),
                            if (session.phase == 'insertion' ||
                                session.phase == 'withdrawal' ||
                                session.phase == 'waiting')
                              _pill(
                                '\u0394 ${(session.liveAngle - session.targetAngle).abs().toStringAsFixed(0)}\u00b0 \u2014 Good',
                                bg: _greenBg,
                                border: _greenBorder,
                                text: _green,
                              ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Metrics preview
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _cardBorder),
                          ),
                          child: Column(
                            children: [
                              _MetricRow(
                                label: 'Insertion Locked',
                                value: session.finalInsertionAngle != null
                                    ? '${session.finalInsertionAngle!.toStringAsFixed(1)}\u00b0 \u00b7 ${session.insertionScore ?? "-"}/5'
                                    : '--',
                                valueColor: session.finalInsertionAngle != null ? _green : _textMid,
                              ),
                              const SizedBox(height: 6),
                              _MetricRow(
                                label: 'Aspiration Phase',
                                value: session.phase == 'aspiration'
                                    ? 'Active\u2026'
                                    : (session.aspirationResult ?? '--'),
                                valueColor: session.phase == 'aspiration' ? _amber : _textMid,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Controls panel ─────────────────────────────────────────
                _buildControls(instructorId, session),
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
          _PhaseStep(label: 'Aspiration', state: _getPhaseState(session.phase, 2)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('\u203a', style: TextStyle(color: _cardBorder, fontSize: 14))),
          _PhaseStep(label: 'Withdrawal', state: _getPhaseState(session.phase, 3)),
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
        hint: 'Tap to begin aspiration hold',
        color: _navy,
        onPressed: guardrailBlocked ? () {} : () => _updatePhase(instructorId, 'aspiration'),
      );
    } else if (session.phase == 'aspiration') {
      button = _ControlButton(
        label: 'Done Aspirating',
        hint: 'Tap to stop timer',
        color: const Color(0xFF92400E),
        onPressed: guardrailBlocked ? () {} : () => _updatePhase(instructorId, 'aspiration_locked'),
      );
    } else if (session.phase == 'aspiration_locked') {
      button = _ControlButton(
        label: 'Proceed to Withdrawal',
        hint: 'Tap to advance phase',
        color: _navy,
        onPressed: guardrailBlocked ? () {} : () => _updatePhase(instructorId, 'withdrawal'),
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
    } else if (step == 2) {
      if (currentPhase == 'insertion_locked' || currentPhase == 'aspiration') return 1;
      if (currentPhase == 'aspiration_locked' || currentPhase == 'withdrawal' || currentPhase == 'withdrawal_locked') return 2;
      return 0;
    } else {
      if (currentPhase == 'aspiration_locked' || currentPhase == 'withdrawal' || currentPhase == 'withdrawal_locked') return 1;
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
