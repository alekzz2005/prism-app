import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/live_session_service.dart';
import '../../services/instructor_session_repository.dart';
import '../../models/session_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final _liveService = LiveSessionService();
  final _repo = InstructorSessionRepository();

  void _updatePhase(String instructorId, String newPhase) {
    _liveService.updatePhase(instructorId, newPhase);
  }

  void _completeSession(String instructorId, LiveSessionModel session) async {
    // Build final session model
    final finalSession = SessionModel(
      sessionId: '', // Auto-generated
      userId: session.studentEmail, // Using email as ID for roster matching
      timestamp: Timestamp.now(), 
      injectionType: session.injectionType,
      insertionAngle: session.finalInsertionAngle ?? 0,
      insertionScore: session.insertionScore ?? 1,
      aspirationResult: session.aspirationResult ?? 'Not Detected',
      aspirationDuration: session.aspirationDuration ?? 0,
      motionSmoothness: session.motionSmoothness ?? 'Low',
      withdrawalAngle: session.finalWithdrawalAngle ?? 0,
      withdrawalScore: session.withdrawalScore ?? 1,
      correspondenceResult: session.correspondenceResult ?? 'Deviates',
      angularDelta: session.angularDelta ?? 0,
      overallScore: (( (session.insertionScore ?? 1) + 
                       (session.withdrawalScore ?? 1) + 
                       ((session.aspirationResult == 'Correct') ? 5 : 1) ) / 3).round(),
      aiFeedbackText: '',
      feedbackStatus: 'Pending',
      instructorNote: '',
      flagged: false,
    );

    await _repo.saveSession(finalSession);
    _liveService.clearSession(instructorId);
    
    if (!mounted) return;
    Navigator.pop(context); // Go back to setup screen or dashboard
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
      return _ControlButton(
        label: 'Start Insertion Phase',
        icon: Icons.play_arrow,
        color: Colors.deepPurpleAccent,
        onPressed: () => _updatePhase(instructorId, 'insertion'),
      );
    } else if (session.phase == 'insertion') {
      return _ControlButton(
        label: 'Confirm Needle Insertion',
        icon: Icons.push_pin,
        color: Colors.amberAccent.shade700,
        onPressed: () => _updatePhase(instructorId, 'insertion_locked'),
      );
    } else if (session.phase == 'insertion_locked') {
      return _ControlButton(
        label: 'Proceed to Aspiration',
        icon: Icons.arrow_forward,
        color: Colors.deepPurpleAccent,
        onPressed: () => _updatePhase(instructorId, 'aspiration'),
      );
    } else if (session.phase == 'aspiration') {
      return _ControlButton(
        label: 'Done Aspirating',
        icon: Icons.stop,
        color: Colors.amberAccent.shade700,
        onPressed: () => _updatePhase(instructorId, 'aspiration_locked'),
      );
    } else if (session.phase == 'aspiration_locked') {
      return _ControlButton(
        label: 'Proceed to Withdrawal',
        icon: Icons.arrow_forward,
        color: Colors.deepPurpleAccent,
        onPressed: () => _updatePhase(instructorId, 'withdrawal'),
      );
    } else if (session.phase == 'withdrawal') {
      return _ControlButton(
        label: 'Confirm Withdrawal',
        icon: Icons.check_circle,
        color: Colors.amberAccent.shade700,
        onPressed: () => _updatePhase(instructorId, 'withdrawal_locked'),
      );
    } else if (session.phase == 'withdrawal_locked') {
      return _ControlButton(
        label: 'Complete & Save Session',
        icon: Icons.save,
        color: Colors.greenAccent.shade700,
        onPressed: () => _completeSession(instructorId, session),
      );
    }
    return const SizedBox();
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        onPressed: onPressed,
      ),
    );
  }
}
