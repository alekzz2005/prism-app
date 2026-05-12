import 'package:flutter/material.dart';
import '../../models/session_model.dart';
import '../../services/instructor_session_repository.dart';
import '../../services/feedback_release_service.dart';

/// UC-4.2 — Instructor reviews AI feedback, adds a note, and releases to student.
class FeedbackReviewScreen extends StatefulWidget {
  final SessionModel session;
  final InstructorSessionRepository repo;

  const FeedbackReviewScreen({
    super.key,
    required this.session,
    required this.repo,
  });

  @override
  State<FeedbackReviewScreen> createState() => _FeedbackReviewScreenState();
}

class _FeedbackReviewScreenState extends State<FeedbackReviewScreen> {
  late final TextEditingController _noteController;
  final _releaseService = FeedbackReleaseService();
  bool _isReleasing = false;

  @override
  void initState() {
    super.initState();
    _noteController =
        TextEditingController(text: widget.session.instructorNote);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _release() async {
    setState(() => _isReleasing = true);
    try {
      await _releaseService.releaseSession(
        widget.session.sessionId,
        _noteController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Released successfully'),
            backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } on ReleaseFailedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isReleasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final date = s.timestamp.toDate();
    final isReleased = s.feedbackStatus == 'Released';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('${s.injectionType} Review',
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${date.day}/${date.month}/${date.year}',
                    style: const TextStyle(color: Colors.white54)),
                _StatusChip(status: s.feedbackStatus),
              ],
            ),
            const SizedBox(height: 4),
            Text('Student: ${s.userId}',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 20),

            // ── Detection results (read-only) ──
            _SectionHeader('Detection Results'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _ResultRow('Insertion',
                      '${s.insertionAngle.toStringAsFixed(1)}°  —  ${s.insertionScore}/5'),
                  _ResultRow('Aspiration',
                      '${s.aspirationResult}  (${s.aspirationDuration.toStringAsFixed(1)}s, ${s.motionSmoothness})'),
                  _ResultRow('Withdrawal',
                      '${s.withdrawalAngle.toStringAsFixed(1)}°  —  ${s.withdrawalScore}/5'),
                  _ResultRow(
                      'Correspondence', s.correspondenceResult),
                  _ResultRow('Angular Delta',
                      '${s.angularDelta.toStringAsFixed(1)}°'),
                  const Divider(color: Colors.white12, height: 20),
                  _ResultRow(
                      'Overall', '${s.overallScore}/5',
                      highlight: true),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── AI Draft (read-only) ──
            _SectionHeader('AI Draft'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                s.aiFeedbackText.isEmpty
                    ? 'No AI feedback was generated.'
                    : s.aiFeedbackText,
                style: const TextStyle(
                    color: Colors.white70,
                    height: 1.6,
                    fontSize: 14),
              ),
            ),
            const SizedBox(height: 20),

            // ── Instructor Note (editable) ──
            _SectionHeader('Instructor Note (optional)'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('instructor_note_field'),
              controller: _noteController,
              maxLines: 5,
              enabled: !isReleased,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Add your clinical notes...',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Colors.deepPurpleAccent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Release button ──
            if (!isReleased)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const Key('release_button'),
                  onPressed: _isReleasing ? null : _release,
                  icon: _isReleasing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Release to Student',
                      style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              )
            else
              _ReleasedBanner(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ReleasedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text('Feedback already released.',
                style: TextStyle(color: Colors.greenAccent)),
          ],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(
          color: Colors.deepPurpleAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1));
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _ResultRow(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: highlight ? Colors.white : Colors.white54,
                    fontSize: 14,
                    fontWeight: highlight
                        ? FontWeight.bold
                        : FontWeight.normal)),
            Text(value,
                style: TextStyle(
                    color: highlight
                        ? Colors.deepPurpleAccent
                        : Colors.white,
                    fontSize: 14,
                    fontWeight: highlight
                        ? FontWeight.bold
                        : FontWeight.normal)),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'Released'
        ? Colors.greenAccent
        : status == 'Pending'
            ? Colors.amberAccent
            : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(status, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
