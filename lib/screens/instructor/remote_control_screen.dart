import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../providers/user_role_provider.dart';
import '../../services/live_session_service.dart';
import '../../services/instructor_session_repository.dart';
import '../../models/session_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Brand Colours ─────────────────────────────────────────────────────────
const _navy       = Color(0xFF003366);
const _navyMid    = Color(0xFF004080);
const _navyDark   = Color(0xFF002244);
const _accentBlue = Color(0xFFA8C4E0);
const _cardBg     = Color(0xFFFFFFFF);
const _cardBorder = Color(0xFFE2EAF4);
const _bg         = Color(0xFFF0F4F8);
const _textMid    = Color(0xFF8A9BB0);
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
  final _repo        = InstructorSessionRepository();

  void _updatePhase(String instructorId, String newPhase) {
    _liveService.updatePhase(instructorId, newPhase);
  }

  void _completeSession(String instructorId, LiveSessionModel session) async {
    final finalSession = SessionModel(
      sessionId:           '',
      userId:              session.studentEmail,
      timestamp:           Timestamp.now(),
      injectionType:       session.injectionType,
      insertionAngle:      session.finalInsertionAngle ?? 0,
      insertionScore:      session.insertionScore ?? 1,
      aspirationResult:    session.aspirationResult ?? 'Not Detected',
      aspirationDuration:  session.aspirationDuration ?? 0,
      motionSmoothness:    session.motionSmoothness ?? 'Low',
      withdrawalAngle:     session.finalWithdrawalAngle ?? 0,
      withdrawalScore:     session.withdrawalScore ?? 1,
      correspondenceResult: session.correspondenceResult ?? 'Deviates',
      angularDelta:        session.angularDelta ?? 0,
      overallScore:        (((session.insertionScore ?? 1) +
                             (session.withdrawalScore ?? 1) +
                             ((session.aspirationResult == 'Correct') ? 5 : 1)) /
                            3)
                           .round(),
      aiFeedbackText:  '',
      feedbackStatus:  'Pending',
      instructorNote:  '',
      flagged:         false,
    );

    await _repo.saveSession(finalSession);
    _liveService.clearSession(instructorId);
    if (!mounted) return;
    Navigator.pop(context);
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
                        Container(
                          width: 180, height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _navy.withValues(alpha: 0.04),
                            border: Border.all(color: _cardBorder, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 160, height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _navy.withValues(alpha: 0.08)),
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

                        const SizedBox(height: 16),

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

                        const SizedBox(height: 18),

                        // Gauge
                        _Gauge(angle: session.liveAngle),

                        const SizedBox(height: 16),

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
                    const Text('Live Demo Control',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
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
      color: _cardBg,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: const BoxDecoration(
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
      return _ControlButton(label: 'Start Insertion Phase', color: _navy,
          hint: 'Tap to begin tracking',
          onPressed: () => _updatePhase(instructorId, 'insertion'));
    } else if (session.phase == 'insertion') {
      return _ControlButton(label: 'Confirm Needle Insertion', color: const Color(0xFF92400E),
          hint: 'Tap when the needle is fully inserted',
          onPressed: () => _updatePhase(instructorId, 'insertion_locked'));
    } else if (session.phase == 'insertion_locked') {
      return _ControlButton(label: 'Proceed to Aspiration', color: _navy,
          hint: 'Tap to begin aspiration hold',
          onPressed: () => _updatePhase(instructorId, 'aspiration'));
    } else if (session.phase == 'aspiration') {
      return _ControlButton(label: 'Done Aspirating', color: const Color(0xFF92400E),
          hint: 'Tap when the student completes the aspiration hold',
          onPressed: () => _updatePhase(instructorId, 'aspiration_locked'));
    } else if (session.phase == 'aspiration_locked') {
      return _ControlButton(label: 'Proceed to Withdrawal', color: _navy,
          hint: 'Tap to begin withdrawal tracking',
          onPressed: () => _updatePhase(instructorId, 'withdrawal'));
    } else if (session.phase == 'withdrawal') {
      return _ControlButton(label: 'Confirm Withdrawal', color: const Color(0xFF92400E),
          hint: 'Tap when the needle is fully withdrawn',
          onPressed: () => _updatePhase(instructorId, 'withdrawal_locked'));
    } else if (session.phase == 'withdrawal_locked') {
      return _ControlButton(label: 'Complete & Save Session', color: const Color(0xFF16A34A),
          hint: 'Tap to finalize and generate feedback',
          onPressed: () => _completeSession(instructorId, session));
    }
    return const SizedBox();
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
