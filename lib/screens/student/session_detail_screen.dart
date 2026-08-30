import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/session_model.dart';
import '../../services/feedback_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../widgets/image_zoom_dialog.dart';

// ─── Brand Colours ────────────────────────────────────────────────────────────
const _navy       = Color(0xFF003366);
const _navyMid    = Color(0xFF004080);
const _navyDark   = Color(0xFF002244);
const _accent     = Color(0xFFA8C4E0);
const _surface    = Color(0xFFF8FAFC);
const _white      = Color(0xFFFFFFFF);
const _border     = Color(0xFFE2EAF4);
const _textDark   = Color(0xFF1A2B3C);
const _textMid    = Color(0xFF4A5568);
const _textLight  = Color(0xFF8A9BB0);

const _green      = Color(0xFF15803D);
const _greenBg    = Color(0x1A22C55E); // 10%
const _amber      = Color(0xFFB45309);
const _amberBg    = Color(0x1AF59E0B);
const _red        = Color(0xFFDC2626);
const _redBg      = Color(0x1AEF4444);
// ─────────────────────────────────────────────────────────────────────────────

class SessionDetailScreen extends StatefulWidget {
  final SessionModel session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  bool _isRetrying = false;

  Future<void> _retryAiFeedback(SessionModel session) async {
    setState(() => _isRetrying = true);
    try {
      await FeedbackService().generateAndSaveFeedbackInBackground(session);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI feedback generation restarted. Please wait a moment...'),
            backgroundColor: _navy,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to restart AI feedback. Please check your connection.'),
            backgroundColor: _red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final config = _targetForType(session.injectionType);
    final target = config['target']!;
    final tolerance = config['tolerance']!;
    final insertionPass = (session.insertionAngle - target).abs() <= tolerance;
    final withdrawalPass = (session.withdrawalAngle - target).abs() <= tolerance;
    final aspirationPass = session.aspirationResult == 'No Bleeding' || session.aspirationResult == 'No' || session.aspirationResult == 'Correct';
    final formattedDate = DateFormat('MMMM d, yyyy · h:mm a').format(session.timestamp.toDate());

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
          }
        }
      },
      child: Scaffold(
        backgroundColor: _surface,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Header (App Bar + Score Hero) ───────────────────────────────
              _buildHeader(context, target, formattedDate),

            // ── Scroll Body ──────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Pending Banner ───────────────────────────────────────────────
                    if (session.feedbackStatus == 'Pending Review')
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0x1AF59E0B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.hourglass_empty_rounded, color: Color(0xFFD97706), size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Pending Review', style: TextStyle(color: Color(0xFFB45309), fontSize: 14, fontWeight: FontWeight.w700)),
                                  SizedBox(height: 2),
                                  Text('This session is still pending instructor review. Please wait.', style: TextStyle(color: Color(0xFFB45309), fontSize: 12, height: 1.4)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Session Snapshots (Top of body, matching Instructor Review) ──
                    if (session.insertionImageBase64 != null || session.aspirationImageBase64 != null || session.withdrawalImageBase64 != null) ...[
                      _sectionLabel('SESSION SNAPSHOTS'),
                      Builder(
                        builder: (context) {
                          final items = <SnapshotImageItem>[
                            if (session.insertionImageBase64 != null)
                              SnapshotImageItem(title: 'Insertion', base64Image: session.insertionImageBase64!),
                            if (session.aspirationImageBase64 != null)
                              SnapshotImageItem(title: 'Aspiration', base64Image: session.aspirationImageBase64!),
                            if (session.withdrawalImageBase64 != null)
                              SnapshotImageItem(title: 'Withdrawal', base64Image: session.withdrawalImageBase64!),
                          ];

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: items.asMap().entries.map((entry) {
                                final index = entry.key;
                                final item = entry.value;
                                return _SnapshotCard(
                                  title: item.title,
                                  base64Image: item.base64Image,
                                  onTap: () => showImageGalleryDialog(
                                    context,
                                    items: items,
                                    initialIndex: index,
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Section 1: Insertion
                    _SectionCard(
                      themeColor: _navy,
                      title: 'Section 1 — Needle Insertion',
                      children: [
                        _DataRow('Measured Angle', '${session.insertionAngle.toStringAsFixed(1)}°', false),
                        _DataRow('Target Angle', '${target.toStringAsFixed(0)}°', false),
                        _DataRow('Deviation', '${(session.insertionAngle - target).abs().toStringAsFixed(1)}°', false),
                        _DataRow('Rubric Score', "${session.insertionScore ?? '—'} / 5", false),
                        _DataRow(
                          'Result', '', true,
                          trailing: _Chip(
                            text: insertionPass ? 'Pass' : 'Fail',
                            textColor: insertionPass ? _green : _red,
                            bgColor: insertionPass ? _greenBg : _redBg,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Section 2: Aspiration
                    _SectionCard(
                      themeColor: const Color(0xFF1E5F8A),
                      title: 'Section 2 — Needle Aspiration',
                      children: [
                        _DataRow('Blood Return Check', session.aspirationResult, false),
                        _DataRow('Clinical Finding', aspirationPass ? 'No Blood (Safe to Inject)' : 'Blood Observed (Vascular Puncture)', false),
                        _DataRow('Rubric Score', "${aspirationPass ? 5 : 1} / 5", false),
                        _DataRow(
                          'Result', '', true,
                          trailing: _Chip(
                            text: aspirationPass ? 'Pass' : 'Fail',
                            textColor: aspirationPass ? _green : _red,
                            bgColor: aspirationPass ? _greenBg : _redBg,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Section 3: Withdrawal
                    _SectionCard(
                      themeColor: const Color(0xFF2E6DA4),
                      title: 'Section 3 — Needle Withdrawal',
                      children: [
                        _DataRow('Withdrawal Angle', '${session.withdrawalAngle.toStringAsFixed(1)}°', false),
                        _DataRow('Angular Delta', '${session.angularDelta.toStringAsFixed(1)}°', false),
                        _DataRow(
                          'Correspondence', '', false,
                          trailing: _Chip(
                            text: session.correspondenceResult,
                            textColor: session.correspondenceResult == 'Matches' ? _green : _amber,
                            bgColor: session.correspondenceResult == 'Matches' ? _greenBg : _amberBg,
                          ),
                        ),
                        _DataRow('Rubric Score', "${session.withdrawalScore ?? '—'} / 5", false),
                        _DataRow(
                          'Result', '', true,
                          trailing: _Chip(
                            text: withdrawalPass ? 'Pass' : 'Fail',
                            textColor: withdrawalPass ? _green : _red,
                            bgColor: withdrawalPass ? _greenBg : _redBg,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Section 4: Feedback (with real-time stream, loading, and retry on error)
                    Builder(
                      builder: (context) {
                        final isPractice = session.sectionName == 'Practice' || session.partnerName == 'Self-Practice';

                        if (session.sessionId.isEmpty) {
                          // In-memory fallback
                          return _buildFeedbackSection(
                            isPractice: isPractice,
                            aiText: session.aiFeedbackText,
                            status: session.feedbackStatus,
                          );
                        }

                        return StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('sessions').doc(session.sessionId).snapshots(),
                          builder: (context, snap) {
                            String streamAiText = session.aiFeedbackText;
                            String streamStatus = session.feedbackStatus;

                            if (snap.hasData && snap.data!.exists) {
                              final data = snap.data!.data() as Map<String, dynamic>?;
                              if (data != null) {
                                streamAiText = data['aiFeedbackText'] as String? ?? streamAiText;
                                streamStatus = data['feedbackStatus'] as String? ?? streamStatus;
                              }
                            }

                            return _buildFeedbackSection(
                              isPractice: isPractice,
                              aiText: streamAiText,
                              status: streamStatus,
                            );
                          },
                        );
                      }
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildFeedbackSection({
    required bool isPractice,
    required String aiText,
    required String status,
  }) {
    final isFailed = status == 'Feedback Generation Failed';
    final isLoading = aiText.isEmpty && !isFailed;

    return _SectionCard(
      themeColor: _accent,
      titleColor: const Color(0xFF3A7CA5),
      title: isPractice ? 'Section 4 — AI Feedback' : 'Section 4 — Instructor & AI Feedback',
      padding: const EdgeInsets.only(top: 14),
      children: [
        if (!isPractice)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                SvgPicture.string(
                  '<svg width="14" height="14" viewBox="0 0 14 14" fill="none"><circle cx="7" cy="7" r="6" stroke="#8A9BB0" stroke-width="1.2"/><path d="M7 6v4M7 4.5v.5" stroke="#8A9BB0" stroke-width="1.3" stroke-linecap="round"/></svg>',
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI-Assisted and reviewed by your clinical instructor.',
                    style: TextStyle(color: _textLight, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

        if (isLoading)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            alignment: Alignment.center,
            child: Column(
              children: const [
                SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: _navy, strokeWidth: 2.2)),
                SizedBox(height: 12),
                Text('Generating clinical AI feedback...', style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('Evaluating insertion angle, aspiration technique, and withdrawal.', style: TextStyle(color: _textLight, fontSize: 11), textAlign: TextAlign.center),
              ],
            ),
          )
        else if (isFailed)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _redBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x33EF4444)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.error_outline_rounded, color: _red, size: 18),
                    SizedBox(width: 8),
                    Text('AI Feedback Generation Failed', style: TextStyle(color: _red, fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Network timeout or AI service busy. You can retry generating clinical feedback.', style: TextStyle(color: _textMid, fontSize: 12)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isRetrying ? null : () => _retryAiFeedback(widget.session),
                  icon: _isRetrying
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                  label: Text(_isRetrying ? 'Retrying...' : 'Retry AI Feedback', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: RawScrollbar(
              thumbColor: _border,
              radius: const Radius.circular(4),
              thickness: 4,
              child: SingleChildScrollView(
                child: Text(
                  aiText.isEmpty ? 'No feedback text available.' : aiText,
                  style: const TextStyle(color: _textMid, fontSize: 15, height: 1.6),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, double target, String formattedDate) {
    final session = widget.session;
    return Container(
      color: _navy,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Decorative circles
          Positioned(
            right: -60, top: -71,
            child: Container(
              width: 209, height: 207,
              decoration: BoxDecoration(color: _navyMid.withValues(alpha: 0.4), shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: -20, top: -30,
            child: Container(
              width: 153, height: 151,
              decoration: BoxDecoration(color: _navyDark.withValues(alpha: 0.3), shape: BoxShape.circle),
            ),
          ),
          Column(
            children: [
              // App bar row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        alignment: Alignment.center,
                        child: SvgPicture.string(
                          '<svg width="18" height="18" viewBox="0 0 18 18" fill="none"><path d="M11 14L6 9L11 4" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.0)),
                        const SizedBox(height: 3),
                        const Text('SESSION DETAIL', style: TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                      ],
                    ),
                  ],
                ),
              ),

              // Hero card
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Column(
                      children: [
                        Text("${session.overallScore ?? '—'}", style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800, height: 1, fontFeatures: [FontFeature.tabularFigures()])),
                        Text('/5', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16, height: 1, fontWeight: FontWeight.w400)),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Container(
                      width: 1, height: 52,
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('OVERALL SCORE', style: TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 1.2)),
                          const SizedBox(height: 6),
                          Text('${_fullType(session.injectionType)} (${session.injectionType})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.1)),
                          const SizedBox(height: 4),
                          Text(formattedDate, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fullType(String abbr) {
    switch(abbr) {
      case 'IM': return 'Intramuscular';
      default: return abbr;
    }
  }

  Map<String, double> _targetForType(String type) {
    const targets = {
      'IM': {'target': 90.0, 'tolerance': 10.0},
    };
    return targets[type] ?? {'target': 0, 'tolerance': 5};
  }
}

class _SectionCard extends StatelessWidget {
  final Color themeColor;
  final Color? titleColor;
  final String title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const _SectionCard({
    required this.themeColor,
    this.titleColor,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(vertical: 2),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x0A001E3C), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Head
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                Container(width: 3, height: 16, decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(color: titleColor ?? themeColor, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;
  final Widget? trailing;

  const _DataRow(this.label, this.value, this.isLast, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0x0A000000))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: const TextStyle(color: _textMid, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          if (trailing != null)
            trailing!
          else
            Expanded(
              flex: 5,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color textColor;
  final Color bgColor;

  const _Chip({required this.text, required this.textColor, required this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

Widget _sectionLabel(String title) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    title,
    style: const TextStyle(color: _navy, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
  ),
);

class _SnapshotCard extends StatelessWidget {
  final String title;
  final String base64Image;
  final VoidCallback onTap;

  const _SnapshotCard({
    required this.title,
    required this.base64Image,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 140,
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Image.memory(
                      base64Decode(base64Image),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Icon(Icons.broken_image, color: _textLight)),
                    ),
                  ),
                ),
                // Zoom icon badge overlay on preview image
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textDark, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


