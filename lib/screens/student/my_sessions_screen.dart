import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/session_model.dart';
import 'session_detail_screen.dart';
import 'practice_mode_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../providers/user_role_provider.dart';
import 'package:provider/provider.dart';
import '../shared/profile_screen.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../../widgets/notification_center_sheet.dart';

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

class _MySessionsScreenState extends State<MySessionsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['Official RDs', 'Practice Mode'];

  bool _fabOpen = false;
  late AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _fabController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  void _toggleFab() {
    setState(() {
      _fabOpen = !_fabOpen;
      if (_fabOpen) _fabController.forward(); else _fabController.reverse();
    });
  }

  void _showPracticeModeModal() {
    _toggleFab();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        decoration: const BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28), topRight: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: _navy.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                child: Center(child: SvgPicture.string(
                  '<svg width="22" height="22" viewBox="0 0 22 22" fill="none">'
                  '<circle cx="11" cy="11" r="7" stroke="#003366" stroke-width="1.7"/>'
                  '<circle cx="11" cy="11" r="2.8" fill="#003366"/>'
                  '<path d="M11 4V2M11 20v-2M4 11H2M20 11h-2" stroke="#003366" stroke-width="1.4" stroke-linecap="round"/>'
                  '</svg>',
                ))),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Practice Mode', style: TextStyle(color: _textDark, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Self-Check · Instant AI Evaluation', style: TextStyle(color: _textMid, fontSize: 11, fontWeight: FontWeight.w500)),
              ]),
            ]),
            const SizedBox(height: 14),
            const Text(
              'Practice your intramuscular injection technique in real time with instant AI feedback upon completion.',
              style: TextStyle(color: _textMid, fontSize: 13, height: 1.5)),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PracticeModeScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
              child: const Text('Launch Practice Mode', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _border, width: 1.5))),
              child: const Text('Cancel', style: TextStyle(color: _textMid, fontSize: 14, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
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
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(context, uid),
                Expanded(
                  child: uid == null
                      ? const Center(child: Text('Not signed in.', style: TextStyle(color: _textMid)))
                      : TabBarView(
                          controller: _tabController,
                          children: const [
                            _SessionList(isPractice: false),
                            _SessionList(isPractice: true),
                          ],
                        ),
                ),
              ],
            ),
          ),

          // FAB backdrop (pure transparent)
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleFab,
                child: const SizedBox.expand(),
              ),
            ),

          // FAB
          Positioned(
            bottom: 24, right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizeTransition(
                  sizeFactor: CurvedAnimation(parent: _fabController, curve: Curves.easeOutBack),
                  axisAlignment: 1.0,
                  child: FadeTransition(
                    opacity: _fabController,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildFabOption(
                        'Practice Mode',
                        '<svg width="20" height="20" viewBox="0 0 20 20" fill="none">'
                        '<circle cx="10" cy="10" r="6.5" stroke="#003366" stroke-width="1.6"/>'
                        '<circle cx="10" cy="10" r="2.5" fill="#003366"/>'
                        '<path d="M10 3.5V2M10 18v-1.5M3.5 10H2M18 10h-1.5" stroke="#003366" stroke-width="1.4" stroke-linecap="round"/>'
                        '</svg>',
                        _showPracticeModeModal),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _toggleFab,
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: _fabOpen ? const Color(0xFF4A6080) : _navy,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.38), blurRadius: 24, offset: const Offset(0, 6))]),
                    child: Stack(alignment: Alignment.center, children: [
                      AnimatedOpacity(
                        opacity: _fabOpen ? 0.0 : 1.0, duration: const Duration(milliseconds: 180),
                        child: SvgPicture.string('<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M12 5v14M5 12h14" stroke="white" stroke-width="2.2" stroke-linecap="round"/></svg>')),
                      AnimatedOpacity(
                        opacity: _fabOpen ? 1.0 : 0.0, duration: const Duration(milliseconds: 180),
                        child: SvgPicture.string('<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><path d="M5 5l12 12M17 5L5 17" stroke="white" stroke-width="2" stroke-linecap="round"/></svg>')),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFabOption(String label, String svg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _navy, borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 4))]),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
        const SizedBox(width: 10),
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(child: SvgPicture.string(svg))),
      ]),
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
                    // Title
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.0)),
                        const SizedBox(height: 3),
                        const Text('MY SESSIONS', style: TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                      ],
                    ),
                    const Spacer(),
                    // Notification Bell with unread badge
                    StreamBuilder<List<NotificationModel>>(
                      stream: NotificationService().watchNotifications(uid ?? ''),
                      builder: (context, snap) {
                        final unread = snap.data?.where((n) => !n.isRead).length ?? 0;
                        return GestureDetector(
                          onTap: () => NotificationCenterSheet.show(context),
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            alignment: Alignment.center,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 20),
                                if (unread > 0)
                                  Positioned(
                                    right: -2, top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFEF4444),
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                                      child: Text(
                                        unread > 9 ? '9+' : '$unread',
                                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }
                    ),
                    const SizedBox(width: 8),
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
                        child: Builder(
                          builder: (context) {
                            final name = context.watch<UserRoleProvider>().fullName ?? 'U';
                            final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
                            return Text(initial, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold));
                          },
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
                      final officialSessions = sessions.where((s) => s.sectionName != 'Practice' && s.partnerName != 'Self-Practice').toList();
                      final practiceSessions = sessions.where((s) => s.sectionName == 'Practice' || s.partnerName == 'Self-Practice').toList();

                      final officialCount = officialSessions.length;
                      final practiceCount = practiceSessions.length;

                      // Official average strictly from released instructor-reviewed sessions
                      final officialScored = officialSessions
                          .where((s) => s.feedbackStatus == 'Released')
                          .map((s) => s.overallScore)
                          .toList();
                      final officialAvg = officialScored.isEmpty
                          ? 0.0
                          : officialScored.reduce((a, b) => a + b) / officialScored.length;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            _ProgressStat(val: '$officialCount', label: 'Official RDs', align: CrossAxisAlignment.center),
                            _ProgressDivider(),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(officialAvg.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1)),
                                      Text('/5', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16, fontWeight: FontWeight.w400)),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  const Text('Official Avg.', style: TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            _ProgressDivider(),
                            _ProgressStat(val: '$practiceCount', label: 'Practice Sets', align: CrossAxisAlignment.center),
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
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
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
          Text(val, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1)),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w600)),
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
  final bool isPractice;

  const _SessionList({required this.isPractice});

  @override
  State<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<_SessionList> with AutomaticKeepAliveClientMixin {
  late final Stream<QuerySnapshot> _stream;
  String _statusFilter = 'All'; // 'All' | 'Released' | 'Pending'
  bool _sortAscending = false; // false = newest first, true = oldest first

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
        final rawSessions = docs
            .map(SessionModel.fromFirestore)
            .where((s) {
              if (widget.isPractice) {
                return s.sectionName == 'Practice' || s.partnerName == 'Self-Practice';
              } else {
                return s.sectionName != 'Practice' && s.partnerName != 'Self-Practice';
              }
            })
            .toList();

        // 1. Sort all sessions chronologically (oldest first) to assign stable sequence numbers
        rawSessions.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final Map<String, int> sessionNumbers = {};
        for (int i = 0; i < rawSessions.length; i++) {
          sessionNumbers[rawSessions[i].sessionId] = i + 1;
        }

        // 2. Filter by status if on Official RDs
        var filteredSessions = rawSessions;
        if (!widget.isPractice && _statusFilter != 'All') {
          filteredSessions = rawSessions.where((s) {
            if (_statusFilter == 'Released') {
              return s.feedbackStatus == 'Released';
            } else {
              return s.feedbackStatus != 'Released';
            }
          }).toList();
        }

        // 3. Sort according to user preference
        if (_sortAscending) {
          filteredSessions.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        } else {
          filteredSessions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }

        return Column(
          children: [
            // Controls row: Instructor-style Dropdown Filter Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  if (!widget.isPractice) ...[
                    Expanded(
                      child: _buildFilterDropdown(
                        'STATUS',
                        ['All', 'Released', 'Pending'],
                        _statusFilter,
                        (v) => setState(() => _statusFilter = v!),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: _buildFilterDropdown(
                      'SORT',
                      ['Latest', 'Oldest'],
                      _sortAscending ? 'Oldest' : 'Latest',
                      (v) => setState(() => _sortAscending = v == 'Oldest'),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: filteredSessions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          widget.isPractice
                              ? 'No self-practice sessions yet.\nTap the + button to launch Practice Mode!'
                              : (_statusFilter == 'All'
                                  ? 'No official return-demonstrations yet.\nYour instructor-supervised RDs will appear here.'
                                  : 'No ${_statusFilter.toLowerCase()} sessions found.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _textLight, fontSize: 14, height: 1.6),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      itemCount: filteredSessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final s = filteredSessions[i];
                        return _SessionTile(
                          session: s,
                          sessionNumber: sessionNumbers[s.sessionId] ?? 1,
                          isPractice: widget.isPractice,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterDropdown(String title, List<String> options, String current, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: _navy, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: current == 'All' || current == 'Latest' ? _border : _navy, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: current,
              isExpanded: true,
              dropdownColor: Colors.white,
              icon: SvgPicture.string('<svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M3 4.5l3 3 3-3" stroke="#8A9BB0" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
              style: const TextStyle(color: _textDark, fontSize: 12, fontWeight: FontWeight.bold),
              items: options.map((o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: TextStyle(color: o == current ? _navy : _textDark, fontWeight: o == current ? FontWeight.bold : FontWeight.w500)),
              )).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Session Tile matching Instructor Blueprint ─────────────────────────────
class _SessionTile extends StatelessWidget {
  final SessionModel session;
  final int sessionNumber;
  final bool isPractice;

  const _SessionTile({
    required this.session,
    required this.sessionNumber,
    required this.isPractice,
  });

  ({Color bg, Color border, Color text}) _statusColors(String status) {
    if (isPractice) return (bg: const Color(0x1F3B82F6), border: const Color(0x333B82F6), text: const Color(0xFF1D4ED8));
    if (status == 'Released') return (bg: _greenBg, border: const Color(0x3322C55E), text: _green);
    if (status == 'Pending' || status == 'Pending Review') return (bg: _amberBg, border: const Color(0x33F59E0B), text: _amber);
    return (bg: _redBg, border: const Color(0x33EF4444), text: _red);
  }

  String _statusLabel(String status) {
    if (isPractice) return 'Practice';
    if (status == 'Feedback Generation Failed') return 'Failed';
    if (status == 'Pending Review') return 'Pending';
    return status;
  }

  @override
  Widget build(BuildContext context) {
    final date = session.timestamp.toDate();
    final isReleased = session.feedbackStatus == 'Released';
    final colors = _statusColors(session.feedbackStatus);

    return GestureDetector(
      key: Key('session_tile_${session.sessionId}'),
      onTap: () {
        if (isReleased || isPractice) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => SessionDetailScreen(session: session)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.hourglass_empty_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This session is still pending instructor review. Please wait.',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFD97706),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
              elevation: 6,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            // Score circle (matching Instructor Card)
            Builder(builder: (context) {
              final score = session.overallScore ?? 0;
              final Color scoreColor;
              final Color scoreBg;
              final Color scoreBorder;
              if (!isReleased && !isPractice) {
                scoreColor = _amber;
                scoreBg = _amberBg;
                scoreBorder = const Color(0x33F59E0B);
              } else if (score >= 4) {
                scoreColor = _green;
                scoreBg = _greenBg;
                scoreBorder = const Color(0x3322C55E);
              } else if (score == 3) {
                scoreColor = _amber;
                scoreBg = _amberBg;
                scoreBorder = const Color(0x33F59E0B);
              } else {
                scoreColor = _red;
                scoreBg = _redBg;
                scoreBorder = const Color(0x33EF4444);
              }

              return Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scoreBg,
                  border: Border.all(color: scoreBorder, width: 1.5),
                ),
                child: Center(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: (isReleased || isPractice) ? '$score' : '—',
                          style: TextStyle(color: scoreColor, fontWeight: FontWeight.w800, fontSize: 18, height: 1),
                        ),
                        TextSpan(
                          text: '/5',
                          style: TextStyle(color: scoreColor.withValues(alpha: 0.55), fontWeight: FontWeight.w600, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 12),

            // Info (matching Instructor Card)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isPractice ? 'Practice #$sessionNumber' : 'Session #$sessionNumber',
                          style: const TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          _statusLabel(session.feedbackStatus),
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isPractice
                        ? '${date.day}/${date.month}/${date.year}  •  ${DateFormat('h:mm a').format(date)}'
                        : '${date.day}/${date.month}/${date.year}  •  ${session.partnerName != null && session.partnerName!.isNotEmpty ? session.partnerName! : '—'}',
                    style: const TextStyle(color: _textMid, fontSize: 12),
                  ),
                ],
              ),
            ),

            // Arrow
            SvgPicture.string(
              '<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M6 4l4 4-4 4" stroke="#E2EAF4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
            ),
          ],
        ),
      ),
    );
  }
}
