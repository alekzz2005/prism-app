import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/session_model.dart';

/// UC-3.3 — Shows full session metrics in 4 sections + AI/Instructor feedback.
class SessionDetailScreen extends StatelessWidget {
  final SessionModel session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final config = _targetForType(session.injectionType);
    final target = config['target']!;
    final tolerance = config['tolerance']!;
    final insertionPass =
        (session.insertionAngle - target).abs() <= tolerance;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('${session.injectionType} Session',
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date + overall score prominent
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.shade900,
                    Colors.deepPurple.shade700,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    '${session.overallScore}/5',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold),
                  ),
                  const Text('Overall Score',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('MMM d, y  h:mm a')
                        .format(session.timestamp.toDate()),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Section 1: Insertion ──
            _SectionCard(
              title: 'Section 1 — Insertion',
              color: Colors.deepPurpleAccent,
              children: [
                _Row('Angle',
                    '${session.insertionAngle.toStringAsFixed(1)}°'),
                _Row('Target', '${target.toStringAsFixed(0)}°'),
                _Row('Score', '${session.insertionScore}/5'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Result',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 14)),
                    _PassFailChip(pass: insertionPass),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Section 2: Aspiration ──
            _SectionCard(
              title: 'Section 2 — Aspiration',
              color: Colors.teal,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Result',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 14)),
                    _AspirationChip(result: session.aspirationResult),
                  ],
                ),
                _Row('Duration',
                    '${session.aspirationDuration.toStringAsFixed(1)}s'),
                _Row('Smoothness', session.motionSmoothness),
              ],
            ),
            const SizedBox(height: 16),

            // ── Section 3: Withdrawal ──
            _SectionCard(
              title: 'Section 3 — Withdrawal',
              color: Colors.indigo,
              children: [
                _Row('Angle',
                    '${session.withdrawalAngle.toStringAsFixed(1)}°'),
                _Row('Angular Delta',
                    '${session.angularDelta.toStringAsFixed(1)}°'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Correspondence',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 14)),
                    _CorrespondenceChip(
                        result: session.correspondenceResult),
                  ],
                ),
                _Row('Score', '${session.withdrawalScore}/5'),
              ],
            ),
            const SizedBox(height: 16),

            // ── Section 4: AI Assisted Feedback ──
            _SectionCard(
              title: 'Section 4 — AI Assisted Feedback',
              color: Colors.amber,
              children: [
                Text(
                  session.aiFeedbackText.isEmpty
                      ? 'No AI feedback was generated for this session.'
                      : session.aiFeedbackText,
                  style: const TextStyle(
                      color: Colors.white70,
                      height: 1.7,
                      fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  '* This feedback was generated by AI and reviewed/edited by your clinical instructor.',
                  style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Map<String, double> _targetForType(String type) {
    const targets = {
      'IM': {'target': 90.0, 'tolerance': 5.0},
      'SubQ': {'target': 45.0, 'tolerance': 5.0},
      'IV': {'target': 15.0, 'tolerance': 3.0},
      'ID': {'target': 10.0, 'tolerance': 3.0},
    };
    return targets[type] ?? {'target': 0, 'tolerance': 5};
  }
}

// ──────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.8)),
            const SizedBox(height: 10),
            const Divider(color: Colors.white12, height: 0),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 14)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _PassFailChip extends StatelessWidget {
  final bool pass;
  const _PassFailChip({required this.pass});

  @override
  Widget build(BuildContext context) {
    final color = pass ? Colors.greenAccent : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(pass ? 'Pass' : 'Fail',
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12)),
    );
  }
}

class _AspirationChip extends StatelessWidget {
  final String result;
  const _AspirationChip({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result == 'Correct'
        ? Colors.greenAccent
        : result == 'Incorrect'
            ? Colors.redAccent
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(result,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12)),
    );
  }
}

class _CorrespondenceChip extends StatelessWidget {
  final String result;
  const _CorrespondenceChip({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result == 'Matches' ? Colors.greenAccent : Colors.amberAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(result,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12)),
    );
  }
}
