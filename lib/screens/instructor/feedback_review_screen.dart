import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/session_model.dart';
import '../../services/instructor_session_repository.dart';
import '../../services/feedback_release_service.dart';

// ─── Brand Colours ─────────────────────────────────────────────────────────
const _navy        = Color(0xFF003366);
const _navyMid     = Color(0xFF004080);
const _navyDark    = Color(0xFF002244);
const _bg          = Color(0xFFF0F4F8);
const _cardBg      = Color(0xFFFFFFFF);
const _cardBorder  = Color(0xFFE2EAF4);
const _textDark    = Color(0xFF003366);
const _textMid     = Color(0xFF8A9BB0);
const _inputBg     = Color(0xFFF8FAFC);
const _inputBorder = Color(0xFF1A2B3C);
const _green       = Color(0xFF1A7A4A);
const _greenBg     = Color(0xFFEEF9F3);
const _greenBorder = Color(0xFFA8D5B8);
const _amber       = Color(0xFFB45309);
const _amberBg     = Color(0xFFFEF9EE);
const _amberBorder = Color(0xFFF6D28A);
const _red         = Color(0xFF991B1B);
const _redBg       = Color(0xFFFEF2F2);
const _redBorder   = Color(0xFFFECACA);
// ──────────────────────────────────────────────────────────────────────────────

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
    _noteController = TextEditingController(text: widget.session.instructorNote);
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
        const SnackBar(content: Text('Released successfully'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } on ReleaseFailedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isReleasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s          = widget.session;
    final date       = s.timestamp.toDate();
    final isReleased = s.feedbackStatus == 'Released';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _buildHeader(s),

            // ── Scroll body ──────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Meta row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${date.day}/${date.month}/${date.year}',
                                style: const TextStyle(color: _textMid, fontSize: 13)),
                            const SizedBox(height: 3),
                            Text(
                              'Student: ${s.userId.length > 8 ? "${s.userId.substring(0, 8)}..." : s.userId}',
                              style: const TextStyle(color: _textMid, fontSize: 12),
                            ),
                          ],
                        ),
                        _StatusChip(status: s.feedbackStatus),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Detection Results
                    _sectionHeader('Detection Results'),
                    _Card(
                      child: Column(
                        children: [
                          _ResultRow(
                            label: 'Insertion',
                            value: '${s.insertionAngle.toStringAsFixed(1)}\u00b0',
                            score: s.insertionScore,
                          ),
                          _ResultRow(
                            label: 'Aspiration',
                            value: s.aspirationResult,
                            subValue: '(${s.aspirationDuration.toStringAsFixed(1)}s, ${s.motionSmoothness})',
                            isValueGreen: s.aspirationResult == 'Correct',
                          ),
                          _ResultRow(
                            label: 'Withdrawal',
                            value: '${s.withdrawalAngle.toStringAsFixed(1)}\u00b0',
                            score: s.withdrawalScore,
                          ),
                          _ResultRow(
                            label: 'Correspondence',
                            value: s.correspondenceResult,
                            isValueGreen: s.correspondenceResult == 'Matches',
                          ),
                          _ResultRow(
                            label: 'Angular Delta',
                            value: '${s.angularDelta.toStringAsFixed(1)}\u00b0',
                          ),
                          Container(height: 1, color: _cardBorder, margin: const EdgeInsets.symmetric(vertical: 6)),
                          _ResultRow(
                            label: 'Overall Score',
                            value: '',
                            score: s.overallScore,
                            highlight: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Flagged banner
                    if (s.flagged) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _redBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _redBorder),
                        ),
                        child: Row(
                          children: [
                            SvgPicture.string(
                              '<svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M7 5v4M7 10.5h.01M5.95 1.9L1.05 10.7A1.4 1.4 0 0 0 2.25 12.6h9.5a1.4 1.4 0 0 0 1.2-1.9L8.05 1.9a1.4 1.4 0 0 0-2.1 0z" stroke="#991B1B" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Aspiration note flagged for manual review (UC-1.2)',
                                style: TextStyle(color: _red, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // AI Draft Feedback
                    _sectionHeader('AI Draft Feedback'),
                    _Card(
                      child: Text(
                        s.aiFeedbackText.isEmpty ? 'No AI feedback was generated.' : s.aiFeedbackText,
                        style: const TextStyle(color: _textMid, fontSize: 13.5, height: 1.65),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Instructor Note
                    _sectionHeader('Instructor Note (optional)'),
                    Container(
                      decoration: BoxDecoration(
                        color: _inputBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _inputBorder, width: 1.5),
                      ),
                      child: TextField(
                        key: const Key('instructor_note_field'),
                        controller: _noteController,
                        maxLines: 4,
                        enabled: !isReleased,
                        style: const TextStyle(color: _textDark, fontSize: 13, height: 1.6),
                        decoration: const InputDecoration(
                          hintText: 'Add your clinical notes...',
                          hintStyle: TextStyle(color: _textMid, fontSize: 13, height: 1.6),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Release / Already-released
                    if (!isReleased)
                      GestureDetector(
                        key: const Key('release_button'),
                        onTap: _isReleasing ? null : _release,
                        child: Container(
                          width: double.infinity,
                          height: 58,
                          decoration: BoxDecoration(
                            color: _navy,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 6))],
                          ),
                          alignment: Alignment.center,
                          child: _isReleasing
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SvgPicture.string(
                                      '<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M4 10l14 0M14 6l4 4-4 4" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('Release to Student',
                                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _greenBg,
                          border: Border.all(color: _greenBorder),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.string(
                              '<svg width="18" height="18" viewBox="0 0 18 18" fill="none"><circle cx="9" cy="9" r="7" stroke="#1A7A4A" stroke-width="1.5"/><path d="M5.5 9l2.5 2.5 4.5-4.5" stroke="#1A7A4A" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                            ),
                            const SizedBox(width: 10),
                            const Text('Feedback already released',
                                style: TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SessionModel s) {
    return Container(
      color: _navy,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -30, top: -71,
            child: Container(
              width: 209, height: 207,
              decoration: BoxDecoration(
                color: _navyMid.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -20, top: 28,
            child: Container(
              width: 153, height: 151,
              decoration: BoxDecoration(
                color: _navyDark.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: SvgPicture.string(
                      '<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M10 12L5 8L10 4" stroke="rgba(255,255,255,0.8)" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${s.injectionType} Injection Review',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
Widget _sectionHeader(String title) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    title.toUpperCase(),
    style: const TextStyle(color: _navy, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
  ),
);

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _cardBorder),
      boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 2))],
    ),
    child: child,
  );
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final int? score;
  final bool highlight;
  final bool isValueGreen;

  const _ResultRow({
    required this.label,
    required this.value,
    this.subValue,
    this.score,
    this.highlight = false,
    this.isValueGreen = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: highlight ? 10 : 8),
      decoration: BoxDecoration(
        border: const Border(bottom: BorderSide(color: _cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: highlight ? _textDark : _textMid,
              fontSize: highlight ? 14 : 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value.isNotEmpty)
                Text(
                  value,
                  style: TextStyle(
                    color: isValueGreen ? _green : _textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (subValue != null) ...[
                const SizedBox(width: 6),
                Text(subValue!, style: const TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
              if (score != null) ...[
                const SizedBox(width: 8),
                _ScoreVisual(score: score!),
                const SizedBox(width: 8),
                Text(
                  '$score${highlight ? " / 5" : "/5"}',
                  style: TextStyle(
                    color: _navy,
                    fontSize: highlight ? 16 : 13,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreVisual extends StatelessWidget {
  final int score;
  const _ScoreVisual({required this.score});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(5, (i) => Container(
      width: 11, height: 11,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        color: i < score ? _navy : _cardBorder,
        borderRadius: BorderRadius.circular(3),
      ),
    )),
  );
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg, border, text;
    if (status == 'Released') { bg = _greenBg; border = _greenBorder; text = _green; }
    else if (status == 'Pending') { bg = _amberBg; border = _amberBorder; text = _amber; }
    else { bg = _redBg.withValues(alpha: 0.5); border = _redBorder; text = _red; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(status, style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
