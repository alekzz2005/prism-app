import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/live_session_service.dart';
import '../../services/instructor_session_repository.dart';
import '../../models/session_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/feedback_service.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final _liveService = LiveSessionService();
  final _repo = InstructorSessionRepository();
  final _feedbackService = FeedbackService();
  bool _completing = false;

  void _updatePhase(String instructorId, String newPhase) {
    _liveService.updatePhase(instructorId, newPhase);
  }

  void _completeSession(String instructorId, LiveSessionModel session) async {
    setState(() => _completing = true);

    String finalUserId = session.studentEmail;

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
    setState(() => _completing = false);
    Navigator.pop(context); // Go back instantly
    
    // Clear live session AFTER popping animation finishes to avoid jitter
    Future.delayed(const Duration(milliseconds: 400), () {
      _liveService.clearSession(instructorId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final instructorId = context.watch<UserRoleProvider>().uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Live Demo Control', style: TextStyle(color: Colors.white, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white54),
          onPressed: () {
            _liveService.clearSession(instructorId!);
            Navigator.pop(context);
          },
        ),
      ),
      body: StreamBuilder<LiveSessionModel?>(
        stream: _liveService.watchSession(instructorId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
          }

          final session = snapshot.data;
          if (session == null) {
            return const Center(
              child: Text('Session ended or not found.', style: TextStyle(color: Colors.white54)),
            );
          }

          return Column(
            children: [
              // ── Student Info Header ──
              Container(
                width: double.infinity,
                color: const Color(0xFF1A1A2E),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(session.studentName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${session.injectionType} • Target: ${session.targetAngle.toStringAsFixed(0)}°', 
                         style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              const Spacer(),

              // ── Live Angle Display ──
              if (session.phase == 'insertion' || session.phase == 'withdrawal') ...[
                const Text('LIVE ANGLE', style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3), width: 2),
                  ),
                  child: Text(
                    '${session.liveAngle.toStringAsFixed(0)}°',
                    style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                ),
              ] else if (session.phase == 'aspiration') ...[
                 const Icon(Icons.play_circle_outline, color: Colors.amberAccent, size: 64),
                 const SizedBox(height: 16),
                 const Text('Aspiration Tracking Active...', style: TextStyle(color: Colors.amberAccent, fontSize: 18)),
                 const SizedBox(height: 8),
                 Text('Live Result: ${session.liveAspirationResult}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                 Text('Duration: ${session.liveAspirationDuration.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ] else if (session.phase == 'aspiration_locked') ...[
                 const Icon(Icons.analytics, color: Colors.greenAccent, size: 64),
                 const SizedBox(height: 16),
                 Text('Result: ${session.aspirationResult ?? "Not Detected"}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                 Text('Duration: ${session.aspirationDuration?.toStringAsFixed(1) ?? "0.0"}s', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                 Text('Smoothness: ${session.motionSmoothness ?? "Low"}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ] else if (session.phase == 'medication_push' || session.phase == 'medication_push_locked') ...[
                 const Icon(Icons.vaccines, color: Colors.blueAccent, size: 64),
                 const SizedBox(height: 16),
                 const Text('Medication Push Phase...', style: TextStyle(color: Colors.blueAccent, fontSize: 18)),
                 const Text('Injecting slowly (~10s/ml). Angle tracking paused.', style: TextStyle(color: Colors.white54, fontSize: 14)),
              ] else ...[
                 const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 64),
                 const SizedBox(height: 16),
                 Text('Phase Locked (${session.phase})', style: const TextStyle(color: Colors.greenAccent, fontSize: 18)),
              ],

              const Spacer(),

              // ── Phase Controls ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: _buildControls(instructorId, session),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControls(String instructorId, LiveSessionModel session) {
    if (session.phase == 'waiting') {
      final canStart = session.cameraNodeActive;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            label: canStart ? 'Start Insertion Phase' : 'Waiting for Camera...',
            icon: canStart ? Icons.play_arrow : Icons.hourglass_empty,
            color: canStart ? Colors.deepPurpleAccent : Colors.grey,
            onPressed: canStart ? () => _updatePhase(instructorId, 'insertion') : null,
          ),
          if (!canStart)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text('Please open Camera Node on the tripod device.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
            )
        ],
      );
    } 

    if (session.phase == 'withdrawal_locked') {
      return SizedBox(
        height: 60,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent.shade700,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: _completing 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save, color: Colors.white),
          label: Text(_completing ? 'Generating AI Feedback...' : 'Complete & Save Session', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: _completing ? null : () => _completeSession(instructorId, session),
        ),
      );
    }

    // Common Guardrails for active tracking phases
    final bool guardrailBlocked = !session.cameraNodeActive || session.detectionLost;
    
    Widget button;
    if (session.phase == 'insertion') {
      button = _ControlButton(
        label: 'Confirm Needle Insertion',
        icon: Icons.push_pin,
        color: Colors.amberAccent.shade700,
        onPressed: guardrailBlocked ? null : () => _updatePhase(instructorId, 'insertion_locked'),
      );
    } else if (session.phase == 'insertion_locked') {
      final isID = session.injectionType == 'ID';
      button = _ControlButton(
        label: isID ? 'Inject Medication (10s/ml)' : 'Proceed to Aspiration',
        icon: Icons.arrow_forward,
        color: Colors.deepPurpleAccent,
        onPressed: guardrailBlocked ? null : () => _updatePhase(instructorId, isID ? 'medication_push' : 'aspiration'),
      );
    } else if (session.phase == 'aspiration') {
      button = _ControlButton(
        label: 'Done Aspirating',
        icon: Icons.stop,
        color: Colors.amberAccent.shade700,
        onPressed: guardrailBlocked ? null : () => _updatePhase(instructorId, 'aspiration_locked'),
      );
    } else if (session.phase == 'aspiration_locked') {
      button = _ControlButton(
        label: 'Inject Medication (10s/ml)',
        icon: Icons.vaccines,
        color: Colors.deepPurpleAccent,
        onPressed: guardrailBlocked ? null : () => _updatePhase(instructorId, 'medication_push'),
      );
    } else if (session.phase == 'medication_push') {
      button = _ControlButton(
        label: 'Done Injecting',
        icon: Icons.check,
        color: Colors.amberAccent.shade700,
        onPressed: guardrailBlocked ? null : () => _updatePhase(instructorId, 'medication_push_locked'),
      );
    } else if (session.phase == 'medication_push_locked') {
      button = _ControlButton(
        label: 'Proceed to Withdrawal',
        icon: Icons.arrow_forward,
        color: Colors.deepPurpleAccent,
        onPressed: guardrailBlocked ? null : () => _updatePhase(instructorId, 'withdrawal'),
      );
    } else if (session.phase == 'withdrawal') {
      button = _ControlButton(
        label: 'Confirm Withdrawal',
        icon: Icons.check_circle,
        color: Colors.amberAccent.shade700,
        onPressed: guardrailBlocked ? null : () => _updatePhase(instructorId, 'withdrawal_locked'),
      );
    } else {
      return const SizedBox();
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
                Text(
                  !session.cameraNodeActive ? 'Camera disconnected' : 'Detection lost. Reposition hand.', 
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)
                ),
              ],
            ),
          ),
        button,
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: Colors.grey.shade800,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(icon, color: onPressed == null ? Colors.white38 : Colors.white),
        label: Text(label, style: TextStyle(color: onPressed == null ? Colors.white38 : Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        onPressed: onPressed,
      ),
    );
  }
}
