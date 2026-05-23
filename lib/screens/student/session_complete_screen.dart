import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../providers/session_state_provider.dart';
import '../../services/feedback_service.dart';
import '../student/injection_type_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
      await _feedbackService.submitSession(session, uid);
      if (mounted) {
        setState(() {
          _feedbackText = 'Your session has been submitted. '
              'Feedback will be available once your instructor releases it.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
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
      backgroundColor: const Color(0xFFE8EDF2),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // App bar
            Container(
              color: const Color(0xFF003366),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              alignment: Alignment.center,
              child: const Text(
                'Session Complete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            // Scrollable body
            Expanded(
              child: Container(
                color: Colors.white,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Overall score hero
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF003366).withValues(alpha: 0.08),
                                border: Border.all(
                                  color: const Color(0xFF003366),
                                  width: 3,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "${session.overallScore ?? '—'}/5",
                                style: const TextStyle(
                                  fontFamily: 'DM Mono',
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A2E4A),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Overall Score',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF4A6080),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Quick result rows
                      _ResultRow('Injection Type', session.currentConfig?.type ?? '—'),
                      _ResultRow('Insertion Angle', "${session.insertionAngle?.toStringAsFixed(1) ?? '—'}°  (${session.insertionScore ?? '—'}/5)"),
                      _ResultRow('Aspiration', session.aspirationResult ?? '—'),
                      _ResultRow('Withdrawal Angle', "${session.withdrawalAngle?.toStringAsFixed(1) ?? '—'}°  (${session.withdrawalScore ?? '—'}/5)"),
                      _ResultRow('Correspondence', session.correspondenceResult ?? '—', isLast: true),
                      const SizedBox(height: 28),

                      // AI Feedback section
                      const Text(
                        'AI FEEDBACK',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Color(0xFF003366),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F8FC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2EAF4)),
                        ),
                        child: _isLoading
                            ? Column(
                                children: [
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: const Color(0xFF003366),
                                      backgroundColor: const Color(0xFF003366).withValues(alpha: 0.12),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Generating AI feedback...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF4A6080),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              )
                            : _error != null
                                ? Text('Error: $_error', style: const TextStyle(color: Colors.redAccent))
                                : Text(
                                    _feedbackText ?? '',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF4A6080),
                                      height: 1.65,
                                    ),
                                  ),
                      ),
                      const SizedBox(height: 28),

                      // Back to home button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          key: const Key('back_to_home_button'),
                          onPressed: _isLoading ? null : _goHome,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF003366),
                            disabledBackgroundColor: const Color(0xFF003366).withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SvgPicture.string(
                                '''<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">
                                  <path d="M3 9l6-6 6 6M5 7v7h3v-4h4v4h3V7" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
                                </svg>''',
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Back to Home',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
  final bool isLast;

  const _ResultRow(this.label, this.value, {this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast ? null : Border(
          bottom: BorderSide(color: const Color(0xFF003366).withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF4A6080),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'DM Mono',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A2E4A),
            ),
          ),
        ],
      ),
    );
  }
}
