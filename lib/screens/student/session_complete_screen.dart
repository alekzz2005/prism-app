import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../providers/session_state_provider.dart';
import '../../models/session_model.dart';
import '../../services/feedback_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../student/injection_type_screen.dart';

/// Shown after all 3 phases complete. Generates AI feedback and saves to Firestore.
class SessionCompleteScreen extends StatefulWidget {
  const SessionCompleteScreen({super.key});

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  final _feedbackService = FeedbackService();
  String? _feedbackText;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _generateFeedback();
  }

  Future<void> _generateFeedback() async {
    final session = context.read<SessionStateProvider>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    try {
      final finalSession = SessionModel(
        sessionId: '',
        userId: uid,
        studentName: FirebaseAuth.instance.currentUser?.displayName ?? FirebaseAuth.instance.currentUser?.email ?? 'Unknown Student',
        timestamp: Timestamp.now(),
        injectionType: session.currentConfig?.type ?? '',
        insertionAngle: session.insertionAngle ?? 0.0,
        insertionScore: session.insertionScore ?? 1,
        aspirationResult: session.aspirationResult ?? 'Not Detected',
        aspirationDuration: session.aspirationDuration ?? 0.0,
        motionSmoothness: session.motionSmoothness ?? 'Good',
        withdrawalAngle: session.withdrawalAngle ?? 0.0,
        withdrawalScore: session.withdrawalScore ?? 1,
        correspondenceResult: session.correspondenceResult ?? 'Deviates',
        angularDelta: session.angularDelta ?? 0.0,
        overallScore: session.overallScore ?? 1,
        aiFeedbackText: '',
        feedbackStatus: 'Pending',
        instructorNote: '',
        flagged: session.flagged,
      );
      
      final genSession = await _feedbackService.generateFeedbackForSession(finalSession);
      await FirebaseFirestore.instance.collection('sessions').add(genSession.toFirestore());

      // Fetch feedback text from session state (already set in submitSession)
      setState(() {
        _feedbackText = 'Your session has been submitted. '
            'Feedback will be available once your instructor releases it.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _goHome() {
    context.read<SessionStateProvider>().resetSession();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const InjectionTypeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStateProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Session Complete',
            style: TextStyle(color: Colors.white)),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall score
            Center(
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.deepPurple.withValues(alpha: 0.2),
                      border: Border.all(
                          color: Colors.deepPurpleAccent, width: 3),
                    ),
                    child: Center(
                      child: Text(
                        '${session.overallScore ?? '—'}/5',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Overall Score',
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Quick results
            _ResultRow('Injection Type',
                session.currentConfig?.type ?? '—'),
            _ResultRow('Insertion Angle',
                '${session.insertionAngle?.toStringAsFixed(1) ?? '—'}°  (${session.insertionScore ?? '—'}/5)'),
            _ResultRow('Aspiration', session.aspirationResult ?? '—'),
            _ResultRow('Withdrawal Angle',
                '${session.withdrawalAngle?.toStringAsFixed(1) ?? '—'}°  (${session.withdrawalScore ?? '—'}/5)'),
            _ResultRow('Correspondence',
                session.correspondenceResult ?? '—'),
            const SizedBox(height: 28),

            // AI feedback card
            const Text('AI FEEDBACK',
                style: TextStyle(
                    color: Colors.deepPurpleAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
              ),
              child: _isLoading
                  ? const Column(
                      children: [
                        CircularProgressIndicator(
                            color: Colors.deepPurpleAccent),
                        SizedBox(height: 12),
                        Text('Generating AI feedback...',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    )
                  : _error != null
                      ? Text('Error: $_error',
                          style:
                              const TextStyle(color: Colors.redAccent))
                      : Text(
                          _feedbackText ?? '',
                          style: const TextStyle(
                              color: Colors.white70,
                              height: 1.6,
                              fontSize: 14),
                        ),
            ),
            const SizedBox(height: 28),

            // Back to home
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('back_to_home_button'),
                onPressed: _isLoading ? null : _goHome,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back to Home',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  const _ResultRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 14)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
