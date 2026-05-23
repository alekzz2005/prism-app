import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/session_model.dart';
import 'session_detail_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/auth_wrapper.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../shared/profile_screen.dart';

// ─── Brand Colours ────────────────────────────────────────────────────────────
const _navy       = Color(0xFF003366);
const _navyMid    = Color(0xFF004080);
const _navyDark   = Color(0xFF002244);
const _accent     = Color(0xFFA8C4E0);
const _surface    = Color(0xFFF8FAFC);
const _white      = Color(0xFFFFFFFF);
const _border     = Color(0xFFE2EAF4);
const _borderMid  = Color(0xFFD0DCE8);
const _textDark   = Color(0xFF1A2B3C);
const _textMid    = Color(0xFF4A5568);
const _textLight  = Color(0xFF8A9BB0);

const _green      = Color(0xFF16A34A);
const _greenBg    = Color(0x1A22C55E); // 10% opacity 22C55E
const _amber      = Color(0xFFD97706);
const _amberBg    = Color(0x1AF59E0B);
const _red        = Color(0xFFDC2626);
const _redBg      = Color(0x1AEF4444);
const _pending    = Color(0xFFB45309);
const _pendingBg  = Color(0x14F59E0B); // 8% opacity
const _pendingBorder = Color(0x40F59E0B); // 25% opacity
// ─────────────────────────────────────────────────────────────────────────────

class MySessionsScreen extends StatefulWidget {
  const MySessionsScreen({super.key});

  @override
  State<MySessionsScreen> createState() => _MySessionsScreenState();
}

class _MySessionsScreenState extends State<MySessionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['IM', 'SubQ', 'IV', 'ID'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _buildAggregateQuery() {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return FirebaseFirestore.instance
        .collection('sessions')
        .where('userId', isEqualTo: email)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── App Header ──────────────────────────────────────────────────
            _buildHeader(context, uid),

            // ── Body / Tab Views ─────────────────────────────────────────────
            Expanded(
              child: uid == null
                  ? const Center(child: Text('Not signed in.', style: TextStyle(color: _textMid)))
                  : TabBarView(
                      controller: _tabController,
                      children: _tabs.map((type) => _SessionList(uid: uid, typeFilter: type)).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String? uid) {
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left spacer (replacing back button)
                    const SizedBox(width: 40),
                    // Title
                    Column(
                      children: [
                        const Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 5, height: 1)),
                        const SizedBox(height: 3),
                        const Text('MY SESSIONS', style: TextStyle(color: _accent, fontSize: 9, fontWeight: FontWeight.w400, letterSpacing: 1.5)),
                      ],
                    ),
                    // Profile / Sign-out
                    GestureDetector(
                      key: const Key('student_signout'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProfileScreen()),
                        );
                      },
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          border: Border.all(color: _accent, width: 2),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        alignment: Alignment.center,
                        child: SvgPicture.string(
                          '<svg width="20" height="18" viewBox="0 0 20 18" fill="none"><path d="M10 10C12.76 10 14.96 7.94 14.96 5.42C14.96 2.9 12.76 0.84 10 0.84C7.24 0.84 5.04 2.9 5.04 5.42C5.04 7.94 7.24 10 10 10Z" stroke="white" stroke-width="1.5"/><path d="M1 17.16C1 13.38 5.03 10.31 10 10.31C14.97 10.31 19 13.38 19 17.16" stroke="white" stroke-width="1.5" stroke-linecap="round"/></svg>',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Progress banner
              if (uid != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _buildAggregateQuery(),
                    builder: (context, snap) {
                      final sessions = snap.data?.docs.map((d) => SessionModel.fromFirestore(d)).toList() ?? [];
                      final total = sessions.length;
                      final released = sessions.where((s) => s.feedbackStatus == 'Released').length;
                      final scored = sessions.where((s) => s.overallScore != null).map((s) => s.overallScore!).toList();
                      final avg = scored.isEmpty ? 0.0 : scored.reduce((a, b) => a + b) / scored.length;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            _ProgressStat(val: '$total', label: 'Total Sessions', align: CrossAxisAlignment.start),
                            _ProgressDivider(),
                            Expanded(
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(avg.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1)),
                                      Text('/5', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13, fontWeight: FontWeight.w400)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text('Avg. Score', style: TextStyle(color: _accent, fontSize: 10, fontWeight: FontWeight.w400)),
                                ],
                              ),
                            ),
                            _ProgressDivider(),
                            _ProgressStat(val: '$released', label: 'Released', align: CrossAxisAlignment.end),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              // Tabs
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  indicatorWeight: 2,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.40),
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  tabs: _tabs.map((t) => Tab(text: t)).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressStat extends StatelessWidget {
  final String val, label;
  final CrossAxisAlignment align;
  const _ProgressStat({required this.val, required this.label, required this.align});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(val, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: _accent, fontSize: 10, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

class _ProgressDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 32,
      color: Colors.white.withValues(alpha: 0.20),
      margin: const EdgeInsets.symmetric(horizontal: 0),
    );
  }
}

class _SessionList extends StatefulWidget {
  final String uid;
  final String typeFilter;

  const _SessionList({required this.uid, required this.typeFilter});

  @override
  State<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<_SessionList> with AutomaticKeepAliveClientMixin {
  late final Stream<QuerySnapshot> _stream;

  @override
  bool get wantKeepAlive => true; // Prevent disposal on tab switch

  @override
  void initState() {
    super.initState();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    _stream = FirebaseFirestore.instance
        .collection('sessions')
        .where('userId', isEqualTo: email)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _navy));
        }

        if (snap.hasError) {
          debugPrint('FIRESTORE ERROR in MySessionsScreen: ${snap.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Unable to load sessions.\nPlease try again later.\nError: ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, height: 1.6, fontSize: 12),
              ),
            ),
          );
        }
        
        final docs = snap.data?.docs ?? [];
        final sessions = docs
            .map(SessionModel.fromFirestore)
            .where((s) => s.injectionType == widget.typeFilter)
            .toList();

        // Sort locally to avoid needing a Firestore composite index
        sessions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        if (sessions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No released ${widget.typeFilter} sessions found.\nCheck back after your instructor releases the feedback.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textLight, fontSize: 14, height: 1.6),
              ),
            ),
          );
        }

        // Split by status for section labels
        final released = sessions.where((s) => s.feedbackStatus == 'Released').toList();
        final pending  = sessions.where((s) => s.feedbackStatus != 'Released').toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (released.isNotEmpty) ...[
              const _SectionLabel('Released'),
              ...released.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SessionTile(session: s),
              )),
            ],
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 6),
              const _SectionLabel('Awaiting Review'),
              ...pending.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SessionTile(session: s),
              )),
            ],
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 2, right: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: _textLight, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final SessionModel session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final date = session.timestamp.toDate();
    final formatted = DateFormat('MMM d, yyyy · h:mm a').format(date);
    final isReleased = session.feedbackStatus == 'Released';

    Color sbColor, sbBg;
    if (!isReleased) {
      sbColor = _pending; sbBg = _pendingBg;
    } else {
      int s = session.overallScore ?? 0;
      if (s >= 4)      { sbColor = _green; sbBg = _greenBg; }
      else if (s == 3) { sbColor = _amber; sbBg = _amberBg; }
      else             { sbColor = _red;   sbBg = _redBg; }
    }

    return GestureDetector(
      key: Key('session_tile_${session.sessionId}'),
      onTap: () {
        if (isReleased) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => SessionDetailScreen(session: session)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This session is still pending instructor review. Please wait.')),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isReleased ? _border : _pendingBorder,
            width: 1.5,
          ),
          boxShadow: const [BoxShadow(color: Color(0x0A001E3C), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            // Score badge
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: sbBg, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: isReleased
                  ? Text("${session.overallScore ?? '—'}/5",
                      style: TextStyle(color: sbColor, fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]))
                  : SvgPicture.string(
                      '<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><circle cx="11" cy="11" r="8" stroke="#D97706" stroke-width="1.6"/><path d="M11 7v4.5l3 2" stroke="#D97706" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                    ),
            ),
            const SizedBox(width: 14),

            // Body
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(session.injectionType, style: const TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isReleased ? const Color(0x1F22C55E) : const Color(0x1FF59E0B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(isReleased ? 'Released' : 'Pending',
                            style: TextStyle(color: isReleased ? const Color(0xFF15803D) : const Color(0xFFB45309), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(formatted, style: const TextStyle(color: _textLight, fontSize: 11)),
                ],
              ),
            ),

            // Arrow
            SvgPicture.string(
              isReleased 
                  ? '<svg width="18" height="18" viewBox="0 0 18 18" fill="none"><path d="M7 4l5 5-5 5" stroke="#D0DCE8" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'
                  : '<svg width="18" height="18" viewBox="0 0 18 18" fill="none"><path d="M7 4l5 5-5 5" stroke="rgba(245,158,11,0.40)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
            ),
          ],
        ),
      ),
    );
  }
}
