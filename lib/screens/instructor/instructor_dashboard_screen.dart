import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/session_model.dart';
import '../../providers/user_role_provider.dart';
import '../../services/auth_service.dart';
import '../../services/instructor_session_repository.dart';
import '../../widgets/auth_wrapper.dart';
import 'feedback_review_screen.dart';
import 'camera_node_screen.dart';
import 'live_demo_setup_screen.dart';
import '../shared/profile_screen.dart';

// ─── Brand Colours ────────────────────────────────────────────────────────────
const _navy     = Color(0xFF003366);
const _navyMid  = Color(0xFF004080);
const _navyDark = Color(0xFF002244);
const _accentBlue = Color(0xFFA8C4E0);
const _bg       = Color(0xFFF0F4F8);
const _cardBg   = Color(0xFFFFFFFF);
const _cardBorder = Color(0xFFE2EAF4);
const _textDark = Color(0xFF003366);
const _textMid  = Color(0xFF8A9BB0);
const _green    = Color(0xFF1A7A4A);
const _greenBg  = Color(0xFFEEF9F3);
const _greenBorder = Color(0xFFA8D5B8);
const _amber    = Color(0xFFB45309);
const _amberBg  = Color(0xFFFEF9EE);
const _amberBorder = Color(0xFFF6D28A);
const _red      = Color(0xFF991B1B);
const _redBg    = Color(0xFFFEF2F2);
const _redBorder = Color(0xFFFECACA);
// ─────────────────────────────────────────────────────────────────────────────

class InstructorDashboardScreen extends StatefulWidget {
  const InstructorDashboardScreen({super.key});

  @override
  State<InstructorDashboardScreen> createState() =>
      _InstructorDashboardScreenState();
}

class _InstructorDashboardScreenState extends State<InstructorDashboardScreen> {
  final _repo = InstructorSessionRepository();

  String _statusFilter = 'All';
  String _typeFilter   = 'All';

  static const _statusOptions = ['All', 'Pending', 'Released', 'Failed'];
  static const _typeOptions   = ['All', 'IM', 'SubQ', 'IV', 'ID'];

  List<SessionModel> _applyFilters(List<SessionModel> sessions) {
    return sessions.where((s) {
      final targetStatus = _statusFilter == 'Failed' ? 'Feedback Generation Failed' : _statusFilter;
      final matchStatus = _statusFilter == 'All' || s.feedbackStatus == targetStatus;
      final matchType   = _typeFilter   == 'All' || s.injectionType   == _typeFilter;
      return matchStatus && matchType;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<UserRoleProvider>();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── App Header ──────────────────────────────────────────────────
            _buildHeader(roleProvider),

            // ── Mode Buttons ────────────────────────────────────────────────
            Container(
              color: _cardBg,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  // Camera Mode (Primary)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const CameraNodeScreen())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                        decoration: BoxDecoration(
                          color: _navy,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 6))],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: SvgPicture.string(
                                '<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><circle cx="10" cy="10" r="7" stroke="white" stroke-width="1.6"/><circle cx="10" cy="10" r="3" fill="white"/></svg>',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('Camera Mode', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
                            Text('(Tripod)', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10, height: 1.2)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Live Demo (Secondary)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const LiveDemoSetupScreen())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border.all(color: _navy, width: 1.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: _navy.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: SvgPicture.string(
                                '<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><rect x="3" y="5" width="14" height="10" rx="2" stroke="#003366" stroke-width="1.6"/><path d="M8 8l4 2-4 2V8z" fill="#003366"/></svg>',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('Live Demo', style: TextStyle(color: _navy, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
                            Text('(Remote)', style: TextStyle(color: _navy.withValues(alpha: 0.7), fontSize: 10, height: 1.2)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Container(color: _cardBg, child: const SizedBox(height: 14)),
            Container(color: _cardBg, child: const Divider(color: _cardBorder, height: 1)),

            // ── Section Header ───────────────────────────────────────────────
            Container(
              color: _cardBg,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Past Sessions', style: TextStyle(color: _textDark, fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
            ),

            // ── Filter Rows ──────────────────────────────────────────────────
            Container(
              color: _cardBg,
              child: Column(
                children: [
                  _FilterRow(label: 'Status:', options: _statusOptions, selected: _statusFilter, onSelected: (v) => setState(() => _statusFilter = v)),
                  _FilterRow(label: 'Type:', options: _typeOptions, selected: _typeFilter, onSelected: (v) => setState(() => _typeFilter = v)),
                ],
              ),
            ),

            Container(color: _cardBg, child: const SizedBox(height: 6)),
            Container(color: _cardBg, child: const Divider(color: _cardBorder, height: 1)),

            // ── Session List ─────────────────────────────────────────────────
            Expanded(
              child: Container(
                color: _cardBg,
                child: StreamBuilder<List<SessionModel>>(
                  stream: _repo.watchAllSessions(
                    statusFilter: _statusFilter == 'All' ? null : _statusFilter,
                    typeFilter:   _typeFilter   == 'All' ? null : _typeFilter,
                  ),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: _navy));
                    }
                    final sessions = _applyFilters(snap.data ?? []);
                    if (sessions.isEmpty) {
                      return const Center(
                        child: Text('No sessions match the current filters.',
                            style: TextStyle(color: _textMid)),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: sessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _SessionCard(session: sessions[i], repo: _repo),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(UserRoleProvider roleProvider) {
    return Container(
      color: _navy,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Decorative circles
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              children: [
                // Top row: brand + sign-out
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 5)),
                        const SizedBox(height: 3),
                        const Text('Injection Skills Monitor', style: TextStyle(color: _accentBlue, fontSize: 10, fontWeight: FontWeight.w400, letterSpacing: 1.5)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GestureDetector(
                          key: const Key('instructor_signout'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ProfileScreen()),
                            );
                          },
                          child: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: _accentBlue, width: 2),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            alignment: Alignment.center,
                            child: SvgPicture.string(
                              '<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M12 12.5C14.2 12.5 16 10.93 16 9s-1.8-3.5-4-3.5-4 1.57-4 3.5 1.8 3.5 4 3.5z" stroke="#003366" stroke-width="1.6"/><path d="M5 19c0-3.31 3.13-6 7-6s7 2.69 7 6" stroke="#003366" stroke-width="1.6" stroke-linecap="round"/></svg>',
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text('Instructor', style: TextStyle(color: _accentBlue, fontSize: 10, fontWeight: FontWeight.w400)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Stats card
                _StatsCard(repo: _repo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Card ────────────────────────────────────────────────────────────────
class _StatsCard extends StatelessWidget {
  final InstructorSessionRepository repo;
  const _StatsCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SessionModel>>(
      stream: repo.watchAllSessions(),
      builder: (context, snap) {
        final sessions = snap.data ?? [];
        final total    = sessions.length;
        final released = sessions.where((s) => s.feedbackStatus == 'Released').length;
        final pending  = sessions.where((s) => s.feedbackStatus == 'Pending').length;
        final scored   = sessions.map((s) => s.overallScore).whereType<int>();
        final avg      = scored.isEmpty ? 0.0 : scored.reduce((a, b) => a + b) / scored.length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              _StatItem(value: '$total',          label: 'Sessions'),
              _StatDivider(),
              _StatItem(value: '$released',        label: 'Released'),
              _StatDivider(),
              _StatItem(value: '$pending',         label: 'Pending'),
              _StatDivider(),
              _StatItem(value: avg.toStringAsFixed(1), label: 'Avg. Score'),
            ],
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value, label;
  const _StatItem({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1.1)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _accentBlue, fontSize: 10, fontWeight: FontWeight.w400)),
      ],
    ),
  );
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 36, margin: const EdgeInsets.symmetric(horizontal: 14),
    color: Colors.white.withValues(alpha: 0.2),
  );
}

// ── Filter Row ────────────────────────────────────────────────────────────────
class _FilterRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _FilterRow({required this.label, required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label, style: const TextStyle(color: _textMid, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: options.map((opt) {
                  final active = opt == selected;
                  return GestureDetector(
                    onTap: () => onSelected(opt),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                      decoration: BoxDecoration(
                        color: active ? _navy : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: active ? _navy : _cardBorder, width: 1.5),
                      ),
                      child: Text(opt, style: TextStyle(color: active ? Colors.white : _textMid, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Session Card ──────────────────────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  final SessionModel session;
  final InstructorSessionRepository repo;
  const _SessionCard({required this.session, required this.repo});

  ({Color bg, Color border, Color text}) _statusColors(String status) {
    if (status == 'Released') return (bg: _greenBg, border: _greenBorder, text: _green);
    if (status == 'Pending')  return (bg: _amberBg, border: _amberBorder, text: _amber);
    return (bg: _redBg, border: _redBorder, text: _red);
  }

  String _statusLabel(String status) {
    if (status == 'Feedback Generation Failed') return 'Failed';
    return status;
  }

  @override
  Widget build(BuildContext context) {
    final date   = session.timestamp.toDate();
    final colors = _statusColors(session.feedbackStatus);

    return GestureDetector(
      key: Key('instructor_session_${session.sessionId}'),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => FeedbackReviewScreen(session: session, repo: repo))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder),
          boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            // Score circle
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.deepPurple.withValues(alpha: 0.2),
                border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Score', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                  Text('${session.overallScore}',
                      style: const TextStyle(
                          color: Colors.deepPurpleAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('${session.injectionType} Injection',
                            style: const TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(_statusLabel(session.feedbackStatus),
                            style: TextStyle(
                                color: colors.text,
                                fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}/${date.month}/${date.year}  •  ${session.studentName}',
                    style: const TextStyle(color: _textMid, fontSize: 12),
                  ),
                ],
              ),
            ),
            SvgPicture.string(
              '<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M6 4l4 4-4 4" stroke="#E2EAF4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
            ),
          ],
        ),
      ),
    );
  }
}
