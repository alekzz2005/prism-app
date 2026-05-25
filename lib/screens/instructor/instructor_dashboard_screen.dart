import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
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
import 'section_students_screen.dart';
import '../shared/profile_screen.dart';
import '../../services/roster_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/live_session_service.dart';
import 'remote_control_screen.dart';

// ─── Brand Colours ────────────────────────────────────────────────────────────
const _navy     = Color(0xFF003366);
const _navyMid  = Color(0xFF004080);
const _navyDark = Color(0xFF002244);
const _accentBlue = Color(0xFFA8C4E0);
const _bg       = Color(0xFFF8FAFC);
const _cardBg   = Color(0xFFFFFFFF);
const _cardBorder = Color(0xFFE2EAF4);
const _textDark = Color(0xFF1A2B3C);
const _textMid  = Color(0xFF4A5568);
const _textLight= Color(0xFF8A9BB0);
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

class _InstructorDashboardScreenState extends State<InstructorDashboardScreen> with SingleTickerProviderStateMixin {
  final _repo = InstructorSessionRepository();
  final _rosterService = RosterService();

  int _currentIndex = 0; // 0: Home, 1: Sections
  bool _fabOpen = false;
  late AnimationController _fabController;

  // Filters for Home
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _typeFilter   = 'All';
  String _sectionFilter = 'All';
  String _schoolYearFilter = 'All';

  static const _statusOptions = ['All', 'Pending', 'Released', 'Failed'];
  static const _typeOptions   = ['All', 'IM'];

  late Stream<List<SessionModel>> _sessionsStream;
  late Stream<List<InstructorSection>> _sectionsStream;
  final Map<String, Stream<List<StudentRoster>>> _rosterStreams = {};

  Stream<List<StudentRoster>> _getRosterStream(String instructorId, String sectionId) {
    final key = '${instructorId}_$sectionId';
    if (!_rosterStreams.containsKey(key)) {
      _rosterStreams[key] = _rosterService.watchRoster(instructorId, sectionId);
    }
    return _rosterStreams[key]!;
  }

  @override
  void initState() {
    super.initState();
    _sessionsStream = _repo.watchAllSessions();
    _fabController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  String? _lastUid;
  List<String> _archivedEmails = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.read<UserRoleProvider>().uid ?? '';
    if (_lastUid != uid) {
      _lastUid = uid;
      if (uid.isNotEmpty) {
        _sectionsStream = _rosterService.watchSections(uid);
        _fetchArchivedEmails(uid);
      } else {
        _sectionsStream = Stream.value([]);
      }
    }
  }

  Future<void> _fetchArchivedEmails(String uid) async {
    try {
      final sections = await FirebaseFirestore.instance.collection('instructor_roster').doc(uid).collection('sections').get();
      List<String> archivedEmails = [];
      for (var sec in sections.docs) {
        final students = await sec.reference.collection('students').where('isArchived', isEqualTo: true).get();
        for (var doc in students.docs) {
          final data = doc.data();
          if (data['email'] != null) {
            archivedEmails.add(data['email'].toString().toLowerCase());
          }
        }
      }
      if (mounted) setState(() => _archivedEmails = archivedEmails);
    } catch (e) {
      debugPrint('Error fetching archived emails: $e');
    }
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  void _toggleFab() {
    setState(() {
      _fabOpen = !_fabOpen;
      if (_fabOpen) {
        _fabController.forward();
      } else {
        _fabController.reverse();
      }
    });
  }

  List<SessionModel> _applyFilters(List<SessionModel> sessions) {
    return sessions.where((s) {
      if (_archivedEmails.contains(s.userId.toLowerCase())) return false; // Hide archived students (userId stores the email)

      final targetStatus = _statusFilter == 'Failed' ? 'Feedback Generation Failed' : _statusFilter;
      final matchStatus = _statusFilter == 'All' || s.feedbackStatus == targetStatus;
      final matchType   = _typeFilter   == 'All' || s.injectionType   == _typeFilter;
      final matchSection = _sectionFilter == 'All' || s.sectionName == _sectionFilter;
      
      final searchLower = _searchQuery.toLowerCase();
      final matchSearch = _searchQuery.isEmpty || 
                          s.studentName.toLowerCase().contains(searchLower) ||
                          s.sessionId.toLowerCase().contains(searchLower);
                          
      return matchStatus && matchType && matchSection && matchSearch;
    }).toList();
  }

  void _showAddSectionModal(String instructorId) {
    _toggleFab(); // close FAB
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddSectionBottomSheet(
        instructorId: instructorId,
        rosterService: _rosterService,
      ),
    );
  }

  void _showCameraModeModal() {
    _toggleFab(); // close FAB
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: _cardBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: _navy.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                  child: Center(
                    child: SvgPicture.string(
                      '<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><circle cx="11" cy="11" r="7" stroke="#003366" stroke-width="1.7"/><circle cx="11" cy="11" r="2.8" fill="#003366"/></svg>',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Camera Mode', style: TextStyle(color: _textDark, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Tripod · Angle Detection', style: TextStyle(color: _textMid, fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Point your device camera at the student\'s injection technique. PRISM will detect angles and phases in real time.',
              style: TextStyle(color: _textMid, fontSize: 13, height: 1.5)),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraNodeScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
              child: const Text('Launch Camera', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _cardBorder, width: 1.5)),
              ),
              child: const Text('Cancel', style: TextStyle(color: _textMid, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<UserRoleProvider>();
    final instructorId = roleProvider.uid;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      _buildDashboardTab(roleProvider),
                      _buildSectionsTab(instructorId),
                    ],
                  ),
                ),
                _buildBottomNav(),
              ],
            ),
          ),

          // FAB Backdrop
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleFab,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.18),
                ),
              ),
            ),
            
          // Shared FAB
          if (instructorId != null)
            Positioned(
              bottom: 84, // Above nav bar
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Options
                  SizeTransition(
                    sizeFactor: CurvedAnimation(parent: _fabController, curve: Curves.easeOutBack),
                    axisAlignment: 1.0,
                    child: FadeTransition(
                      opacity: _fabController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: _currentIndex == 0
                            ? [
                                // Dashboard Options
                                _buildFabOption('Camera Mode', 
                                  '<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><circle cx="10" cy="10" r="6.5" stroke="#003366" stroke-width="1.6"/><circle cx="10" cy="10" r="2.5" fill="#003366"/><path d="M10 3.5V2M10 18v-1.5M3.5 10H2M18 10h-1.5" stroke="#003366" stroke-width="1.4" stroke-linecap="round"/></svg>',
                                  _showCameraModeModal),
                                const SizedBox(height: 8),
                                _buildFabOption('Live Demo',
                                  '<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><rect x="2" y="5" width="13" height="9" rx="2" stroke="#003366" stroke-width="1.6"/><path d="M15 8l3-2v8l-3-2V8z" stroke="#003366" stroke-width="1.6" stroke-linejoin="round"/></svg>',
                                  () {
                                    _toggleFab();
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => _LiveDemoBottomSheet(
                                        instructorId: instructorId,
                                        rosterService: _rosterService,
                                        liveSessionService: LiveSessionService(),
                                      ),
                                    );
                                  }),
                                const SizedBox(height: 10),
                              ]
                            : [
                                // Sections Options
                                _buildFabOption('Add Section',
                                  '<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><rect x="2.5" y="4" width="15" height="12" rx="2.5" stroke="#003366" stroke-width="1.6"/><path d="M6 10h8M10 6v8" stroke="#003366" stroke-width="1.6" stroke-linecap="round"/></svg>',
                                  () => _showAddSectionModal(instructorId)),
                                const SizedBox(height: 10),
                              ],
                      ),
                    ),
                  ),
                  
                  // Main FAB Button
                  GestureDetector(
                    onTap: _toggleFab,
                    child: Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: _fabOpen ? const Color(0xFF4A6080) : _navy,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.38), blurRadius: 24, offset: const Offset(0, 6))],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedOpacity(
                            opacity: _fabOpen ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 180),
                            child: Transform.rotate(
                              angle: _fabOpen ? 0.785 : 0, // 45 deg in rad
                              child: SvgPicture.string('<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M12 5v14M5 12h14" stroke="white" stroke-width="2.2" stroke-linecap="round"/></svg>'),
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: _fabOpen ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 180),
                            child: Transform.rotate(
                              angle: _fabOpen ? 0 : -0.785,
                              child: SvgPicture.string('<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><path d="M5 5l12 12M17 5L5 17" stroke="white" stroke-width="2" stroke-linecap="round"/></svg>'),
                            ),
                          ),
                        ],
                      ),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _cardBorder, width: 2),
              boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: Center(child: SvgPicture.string(svg)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.only(top: 10, bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _cardBorder)),
        boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          _buildNavItem(0, 'Home', 
            '<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><path d="M4.583 9.167v8.25c0 .503.422.916.917.916h3.667v-4.583h3.666v4.583H16.5c.495 0 .917-.413.917-.916V9.167" stroke="COLOR" stroke-width="1.833" stroke-linecap="round" stroke-linejoin="round"/><path d="M2.75 11L11 2.75 19.25 11" stroke="COLOR" stroke-width="1.833" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
          _buildNavItem(1, 'Sections',
            '<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><path d="M7.333 12.833H7.342M11 12.833H11.009M14.667 12.833H14.676M7.333 16.5H7.342M11 16.5H11.009M14.667 16.5H14.676" stroke="COLOR" stroke-width="2.29" stroke-linecap="round"/><path d="M14.667 1.833V5.5M7.333 1.833V5.5M2.75 9.167H19.25" stroke="COLOR" stroke-width="1.833" stroke-linecap="round"/><path d="M17.417 3.667H4.583c-1.012 0-1.833.82-1.833 1.833V18.333c0 1.013.82 1.834 1.833 1.834H17.417c1.012 0 1.833-.821 1.833-1.834V5.5c0-1.012-.82-1.833-1.833-1.833z" stroke="COLOR" stroke-width="1.833"/></svg>'),
          _buildNavItem(2, 'Profile',
            '<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><path d="M3.667 18.333c0-3.666 3.3-6.416 7.333-6.416s7.333 2.75 7.333 6.416" stroke="COLOR" stroke-width="1.833" stroke-linecap="round"/><path d="M11 11c2.025 0 3.667-1.642 3.667-3.667S13.025 3.667 11 3.667 7.333 5.308 7.333 7.333 8.975 11 11 11z" fill="#EAF0F8" stroke="COLOR" stroke-width="1.833"/></svg>'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String label, String svgTpl) {
    final isActive = _currentIndex == index;
    final colorStr = isActive ? '#003366' : '#8A9BB0'; // navy or textMid
    final color = isActive ? _navy : _textMid;
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (index == 2) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
          } else {
            setState(() => _currentIndex = index);
            if (index == 0) {
              final uid = context.read<UserRoleProvider>().uid;
              if (uid != null) _fetchArchivedEmails(uid);
            }
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            SvgPicture.string(svgTpl.replaceAll('COLOR', colorStr)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ── Dashboard Tab ───────────────────────────────────────────────────────────
  Widget _buildDashboardTab(UserRoleProvider roleProvider) {
    return Column(
      children: [
        _buildHeader(roleProvider, "Injection Skills Monitor"),
        
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cardBorder, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                SvgPicture.string(
                  '<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><circle cx="7" cy="7" r="4.5" stroke="#8A9BB0" stroke-width="1.4"/><path d="M10.5 10.5l3 3" stroke="#8A9BB0" stroke-width="1.4" stroke-linecap="round"/></svg>',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: const InputDecoration(
                      hintText: 'Search by student...',
                      hintStyle: TextStyle(color: _textMid, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: const TextStyle(color: _textDark, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(child: _buildFilterDropdown('STATUS', _statusOptions, _statusFilter, (v) => setState(() => _statusFilter = v!))),
              const SizedBox(width: 8),
              Expanded(child: _buildFilterDropdown('TYPE', _typeOptions, _typeFilter, (v) => setState(() => _typeFilter = v!))),
              const SizedBox(width: 8),
              Expanded(
                child: StreamBuilder<List<InstructorSection>>(
                  stream: _sectionsStream,
                  builder: (context, snap) {
                    final List<String> dynamicSections = ['All'];
                    if (snap.hasData) {
                      dynamicSections.addAll(snap.data!.map((e) => e.name).toSet());
                    }
                    return _buildFilterDropdown('SECTION', dynamicSections, _sectionFilter, (v) => setState(() => _sectionFilter = v!));
                  }
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Container(height: 1, color: _cardBorder),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Past Sessions', style: TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.bold)),
              StreamBuilder<List<SessionModel>>(
                stream: _sessionsStream,
                builder: (context, snap) {
                  final len = _applyFilters(snap.data ?? []).length;
                  return Text('$len sessions', style: const TextStyle(color: _navy, fontSize: 12, fontWeight: FontWeight.w600));
                }
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<List<SessionModel>>(
            stream: _sessionsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _navy));
              }
              final sessions = _applyFilters(snap.data ?? []);
              if (sessions.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: 0.35,
                          child: SvgPicture.string(
                            '<svg width="40" height="40" viewBox="0 0 40 40" fill="none"><circle cx="18" cy="18" r="11" stroke="#8A9BB0" stroke-width="2"/><path d="M26 26l7 7" stroke="#8A9BB0" stroke-width="2" stroke-linecap="round"/></svg>',
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text('No sessions found', style: TextStyle(color: _textMid, fontSize: 14, fontWeight: FontWeight.w500)),
                        const Text('Try adjusting your filters or search term', style: TextStyle(color: _textMid, fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: sessions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _SessionCard(session: sessions[i], repo: _repo),
              );
            },
          ),
        ),
      ],
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
            border: Border.all(color: current == 'All' ? _cardBorder : _navy, width: 1.5),
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

  // ── Sections Tab ────────────────────────────────────────────────────────────
  Widget _buildSectionsTab(String? instructorId) {
    if (instructorId == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context.read<UserRoleProvider>(), "Sections & Students"),
        
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('My Sections', style: TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.bold)),
              StreamBuilder<List<InstructorSection>>(
                stream: _sectionsStream,
                builder: (context, snap) {
                  final len = snap.data?.length ?? 0;
                  return Text('$len sections', style: const TextStyle(color: _navy, fontSize: 12, fontWeight: FontWeight.w600));
                }
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: StreamBuilder<List<InstructorSection>>(
            stream: _sectionsStream,
            builder: (context, snap) {
              final List<String> syOptions = ['All'];
              if (snap.hasData) {
                syOptions.addAll(snap.data!.map((e) => e.schoolYear).where((sy) => sy != 'Default').toSet());
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: _buildFilterDropdown('SCHOOL YEAR', syOptions, _schoolYearFilter == '' ? 'All' : _schoolYearFilter, (v) {
                        if (v != null) setState(() => _schoolYearFilter = v);
                      }),
                    ),
                    const Spacer(),
                  ],
                ),
              );
            }
          ),
        ),

        Expanded(
          child: Builder(
            builder: (context) {
              return StreamBuilder<List<InstructorSection>>(
                stream: _sectionsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: _navy));
                  }
                  var sections = snapshot.data ?? [];
                  if (_schoolYearFilter != 'All') {
                    sections = sections.where((s) => s.schoolYear == _schoolYearFilter).toList();
                  }

                  if (sections.isEmpty) {
                    return const Center(child: Text('No sections found.', style: TextStyle(color: _textMid)));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: sections.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final section = sections[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => SectionStudentsScreen(section: section)));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _cardBorder),
                            boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 2))],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(color: _navy.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(13)),
                                alignment: Alignment.center,
                                child: SvgPicture.string('<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" stroke="#003366" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><circle cx="9" cy="7" r="4" stroke="#003366" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" stroke="#003366" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(section.name, style: const TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 3),
                                    Text('Academic Year ${section.schoolYear}', style: const TextStyle(color: _textMid, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: _navy.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(20)),
                                child: StreamBuilder<List<StudentRoster>>(
                                  stream: _getRosterStream(instructorId, section.id),
                                  builder: (context, snap) {
                                    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                                      return const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: _navy));
                                    }
                                    final count = snap.data?.length ?? 0;
                                    return Text('$count students', style: const TextStyle(color: _navy, fontSize: 12, fontWeight: FontWeight.bold));
                                  }
                                ),
                              ),
                              const SizedBox(width: 8),
                              SvgPicture.string('<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M6 4l4 4-4 4" stroke="#C8D8E8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(UserRoleProvider roleProvider, String subtitle) {
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
                        const Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.0)),
                        const SizedBox(height: 3),
                        Text(subtitle.toUpperCase(), style: const TextStyle(color: _accentBlue, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                    ],
                  ),
                ],
              ),
              if (_currentIndex == 0) ...[
                const SizedBox(height: 14),
                // Stats card
                _StatsCard(repo: _repo),
              ]
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, style: const TextStyle(color: _accentBlue, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
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

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
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
            Builder(builder: (context) {
              final score = session.overallScore ?? 0;
              final Color scoreColor;
              final Color scoreBg;
              final Color scoreBorder;
              if (score >= 4) {
                scoreColor = _green;
                scoreBg = _greenBg;
                scoreBorder = _greenBorder;
              } else if (score == 3) {
                scoreColor = _amber;
                scoreBg = _amberBg;
                scoreBorder = _amberBorder;
              } else {
                scoreColor = _red;
                scoreBg = _redBg;
                scoreBorder = _redBorder;
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
                          text: '$score',
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

class _AddSectionBottomSheet extends StatefulWidget {
  final String instructorId;
  final RosterService rosterService;
  const _AddSectionBottomSheet({required this.instructorId, required this.rosterService});

  @override
  State<_AddSectionBottomSheet> createState() => _AddSectionBottomSheetState();
}

class _AddSectionBottomSheetState extends State<_AddSectionBottomSheet> {
  final _nameCtrl = TextEditingController();
  final _syCtrl = TextEditingController(text: '2025-2026');
  bool _isLoading = false;
  String? _errorMsg;
  String? _selectedFileName;
  Uint8List? _selectedFileBytes;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _syCtrl.dispose();
    super.dispose();
  }

  void _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _selectedFileBytes = result.files.single.bytes;
        _selectedFileName = result.files.single.name;
      });
    }
  }

  void _createSection() async {
    final name = _nameCtrl.text.trim();
    final sy = _syCtrl.text.trim();
    if (name.isEmpty || sy.isEmpty || widget.instructorId.isEmpty) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    
    try {
      final docId = '${name}_${sy}';
      final docRef = FirebaseFirestore.instance
          .collection('instructor_roster')
          .doc(widget.instructorId)
          .collection('sections')
          .doc(docId);
          
      final docSnap = await docRef.get();
      if (docSnap.exists) {
        if (mounted) {
          setState(() {
            _errorMsg = 'A section with this name and A.Y already exists.';
            _isLoading = false;
          });
        }
        return;
      }

      await docRef.set({
            'createdAt': FieldValue.serverTimestamp(),
            'schoolYear': sy,
            'name': name,
          });

      if (_selectedFileBytes != null && _selectedFileName != null) {
        await widget.rosterService.importRoster(
          widget.instructorId,
          docId,
          _selectedFileBytes!,
          _selectedFileName!,
        );
      }
    } catch (e) {
      debugPrint('Error creating section: $e');
    }
        
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
              child: Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: _cardBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: _navy.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                  child: Center(
                    child: SvgPicture.string(
                      '<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><rect x="2.5" y="4" width="17" height="14" rx="2.5" stroke="#003366" stroke-width="1.7"/><path d="M11 8v6M8 11h6" stroke="#003366" stroke-width="1.7" stroke-linecap="round"/></svg>',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add Section', style: TextStyle(color: _textDark, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Create a new class section', style: TextStyle(color: _textMid, fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('SECTION NAME', style: TextStyle(color: _navy, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Container(
              height: 46,
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _cardBorder, width: 1.5)),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _nameCtrl,
                textAlign: TextAlign.left,
                decoration: const InputDecoration(hintText: 'e.g. N1, N2', hintStyle: TextStyle(color: _textMid, fontSize: 13), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                style: const TextStyle(color: _textDark, fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),
            const Text('A.Y', style: TextStyle(color: _navy, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Container(
              height: 46,
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _cardBorder, width: 1.5)),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: TextField(
                  controller: _syCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. 2025-2026',
                    hintStyle: TextStyle(color: _textMid, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('UPLOAD STUDENT ROSTER (OPTIONAL)', style: TextStyle(color: _navy, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: _cardBorder, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.string(
                        '<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M10 13V4M10 4L7 7M10 4l3 3" stroke="#003366" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 14v1a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-1" stroke="#8A9BB0" stroke-width="1.4" stroke-linecap="round"/></svg>',
                      ),
                      const SizedBox(width: 10),
                      Text(_selectedFileName ?? 'Upload Spreadsheet (CSV, XLSX) or Add it Later', style: const TextStyle(color: _navy, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            
            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCA5A5))),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12, fontWeight: FontWeight.w500))),
                    ],
                  ),
                ),
              ),
              
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _createSection,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
              child: _isLoading 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Create Section', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _cardBorder, width: 1.5)),
              ),
              child: const Text('Cancel', style: TextStyle(color: _textMid, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ),
  );
}
}



class _LiveDemoBottomSheet extends StatefulWidget {
  final String instructorId;
  final RosterService rosterService;
  final LiveSessionService liveSessionService;

  const _LiveDemoBottomSheet({
    Key? key,
    required this.instructorId,
    required this.rosterService,
    required this.liveSessionService,
  }) : super(key: key);

  @override
  State<_LiveDemoBottomSheet> createState() => _LiveDemoBottomSheetState();
}

class _LiveDemoBottomSheetState extends State<_LiveDemoBottomSheet> {
  int _step = 1;
  String? _selectedSection;
  StudentRoster? _selectedStudent;
  String? _selectedInjectionType; // Only allowing one for now

  Stream<List<InstructorSection>>? _sectionsStream;
  Stream<List<StudentRoster>>? _rosterStream;

  @override
  void initState() {
    super.initState();
    _sectionsStream = widget.rosterService.watchSections(widget.instructorId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _migrateOldSections());
  }

  Future<void> _migrateOldSections() async {
    final db = FirebaseFirestore.instance;
    final sectionsRef = db.collection('instructor_roster').doc(widget.instructorId).collection('sections');
    final snap = await sectionsRef.get();
    
    int year = 2020;
    for (var doc in snap.docs) {
      if (!doc.id.contains('_')) {
        final data = doc.data();
        final newSy = '$year-${year + 1}';
        final newId = '${doc.id}_$newSy';
        
        await sectionsRef.doc(newId).set({
          'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
          'schoolYear': newSy,
          'name': data['name'] ?? doc.id,
        });
        
        final studentsSnap = await doc.reference.collection('students').get();
        if (studentsSnap.docs.isNotEmpty) {
          final batch = db.batch();
          for (var sDoc in studentsSnap.docs) {
            batch.set(sectionsRef.doc(newId).collection('students').doc(sDoc.id), sDoc.data());
            batch.delete(sDoc.reference);
          }
          await batch.commit();
        }
        await doc.reference.delete();
        year++;
      }
    }
  }

  // Injection Type Defs
  final List<Map<String, String>> _injectionTypes = [
    {'key': 'im', 'abbr': 'IM', 'full': 'Intramuscular', 'angle': '90°', 'sites': 'Deltoid, Vastus Lateralis'},
  ];

  Color _getInjColor(String key) {
    switch (key) {
      case 'im': return const Color(0xFF1D4ED8);
      default: return const Color(0xFF003366);
    }
  }

  Color _getInjBg(String key) {
    switch (key) {
      case 'im': return const Color(0xFFEFF6FF);
      default: return Colors.white;
    }
  }

  Color _getInjBorder(String key) {
    switch (key) {
      case 'im': return const Color(0xFFBFDBFE);
      case 'sc': return const Color(0xFFA7F3D0);
      case 'iv': return const Color(0xFFDDD6FE);
      case 'id': return const Color(0xFFFDE68A);
      default: return const Color(0xFFE2EAF4);
    }
  }

  void _startSession() async {
    if (_selectedStudent == null || _selectedInjectionType == null) return;
    final typeKey = _selectedInjectionType!;
    final typeObj = _injectionTypes.firstWhere((t) => t['key'] == typeKey);
    final typeAbbr = typeObj['abbr']!;
    
    // Mapping angle string to double
    double targetAngle = 90.0;
    if (typeKey == 'sc') targetAngle = 45.0;
    else if (typeKey == 'iv') targetAngle = 15.0;
    else if (typeKey == 'id') targetAngle = 10.0;

    await widget.liveSessionService.startSession(
      instructorId: widget.instructorId,
      studentName: _selectedStudent!.formattedFullName,
      studentEmail: _selectedStudent!.email,
      injectionType: typeAbbr,
      targetAngle: targetAngle,
      sectionName: _selectedSection,
    );

    if (mounted) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => const RemoteControlScreen()));
    }
  }

  Widget _buildStep1() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF003366).withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: SvgPicture.string(
                  '<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><rect x="2" y="5.5" width="14" height="10" rx="2" stroke="#003366" stroke-width="1.7"/><path d="M16 9l4-2.5v9L16 13V9z" stroke="#003366" stroke-width="1.7" stroke-linejoin="round"/></svg>',
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live Demo', style: TextStyle(color: Color(0xFF003366), fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Step 1 of 2 · Select a section', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Choose a section to see the student roster.', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 12)),
        const SizedBox(height: 14),
        StreamBuilder<List<InstructorSection>>(
          stream: _sectionsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
            }
            final sections = snapshot.data ?? [];
            if (sections.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No sections found.', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 13))),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sections.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2EAF4)),
              itemBuilder: (context, index) {
                final sec = sections[index];
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedSection = sec.name;
                      _rosterStream = widget.rosterService.watchRoster(widget.instructorId, sec.id);
                      _step = 2;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: const Color(0xFF003366).withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
                          child: Center(
                            child: SvgPicture.string(
                              '<svg width="18" height="18" viewBox="0 0 18 18" fill="none"><path d="M14 16v-1.5a3 3 0 0 0-3-3H7a3 3 0 0 0-3 3V16" stroke="#003366" stroke-width="1.5" stroke-linecap="round"/><circle cx="9" cy="7" r="3" stroke="#003366" stroke-width="1.5"/></svg>'
                            )
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sec.name, style: const TextStyle(color: Color(0xFF003366), fontSize: 14, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        SvgPicture.string('<svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M5 3l4 4-4 4" stroke="#C8D8E8" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2EAF4), width: 1.5)),
          ),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => setState(() {
                _step = 1;
                _selectedStudent = null;
                _selectedInjectionType = null;
              }),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(color: const Color(0xFF003366).withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                child: Center(
                  child: SvgPicture.string('<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M10 12L5 8 10 4" stroke="#003366" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>')
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selectedSection ?? '', style: const TextStyle(color: Color(0xFF003366), fontSize: 14, fontWeight: FontWeight.bold)),
                  const Text('Step 2 of 2 · Select student & injection', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 11)),
                ],
              ),
            ),
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF003366).withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: SvgPicture.string('<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><rect x="2" y="5" width="12" height="9" rx="2" stroke="#003366" stroke-width="1.5"/><path d="M14 7.5l4-2.5v8l-4-2.5V7.5z" stroke="#003366" stroke-width="1.5" stroke-linejoin="round"/></svg>')
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Tap a student to expand, then select an injection type.', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 12)),
        const SizedBox(height: 12),
        StreamBuilder<List<StudentRoster>>(
          stream: _rosterStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
            }
            final students = snapshot.data ?? [];
            if (students.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No students found in this section.', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 13))),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: students.length,
              itemBuilder: (context, index) {
                final s = students[index];
                final isSelected = _selectedStudent?.email == s.email;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF003366).withValues(alpha: 0.035) : Colors.white,
                    border: Border.all(color: isSelected ? const Color(0xFF003366) : const Color(0xFFE2EAF4), width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedStudent = null;
                              _selectedInjectionType = null;
                            } else {
                              _selectedStudent = s;
                              _selectedInjectionType = null;
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.formattedFullName, style: const TextStyle(color: Color(0xFF003366), fontSize: 14, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 1),
                                    Text(s.email, style: const TextStyle(color: Color(0xFF8A9BB0), fontSize: 11)),
                                  ],
                                ),
                              ),
                              AnimatedRotation(
                                turns: isSelected ? 0.25 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: SvgPicture.string('<svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M5 3l4 4-4 4" stroke="#C8D8E8" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: Color(0xFFE2EAF4))),
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(13), bottomRight: Radius.circular(13))
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 4, bottom: 8),
                                child: Text('SELECT INJECTION TYPE', style: TextStyle(color: Color(0xFF003366), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                              ),
                              ..._injectionTypes.map((type) {
                                final isChecked = _selectedInjectionType == type['key'];
                                final c = _getInjColor(type['key']!);
                                final bg = _getInjBg(type['key']!);
                                final border = _getInjBorder(type['key']!);
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedInjectionType = type['key'];
                                    });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isChecked ? const Color(0xFF003366).withValues(alpha: 0.03) : Colors.white,
                                      border: Border.all(color: isChecked ? const Color(0xFF003366) : const Color(0xFFE2EAF4), width: 1.5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36, height: 36,
                                          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(10)),
                                          child: Center(
                                            child: Text(type['abbr']!, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Text(type['full']!, style: const TextStyle(color: Color(0xFF003366), fontSize: 13, fontWeight: FontWeight.bold)),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                                                child: Text(type['angle']!, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          width: 20, height: 20,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white,
                                            border: Border.all(
                                              color: isChecked ? const Color(0xFF003366) : const Color(0xFFCBD5E0),
                                              width: 2,
                                            ),
                                          ),
                                          child: isChecked
                                              ? Center(
                                                  child: Container(
                                                    width: 10,
                                                    height: 10,
                                                    decoration: const BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: Color(0xFF003366),
                                                    ),
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: (_selectedStudent != null && _selectedInjectionType != null) ? _startSession : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF003366),
            disabledBackgroundColor: const Color(0xFFB0C0D4),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 4,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.string('<svg width="18" height="18" viewBox="0 0 18 18" fill="none"><circle cx="9" cy="9" r="7.5" stroke="white" stroke-width="1.5"/><path d="M7 6l5.5 3L7 12V6z" fill="white"/></svg>'),
              const SizedBox(width: 10),
              const Text('Start Session', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2EAF4), width: 1.5)),
          ),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF8A9BB0), fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: const Color(0xFFE2EAF4), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              if (_step == 1) _buildStep1() else _buildStep2(),
            ],
          ),
        ),
      ),
    );
  }
}


