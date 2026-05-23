import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../providers/user_role_provider.dart';
import '../../services/roster_service.dart';
import '../../services/live_session_service.dart';
import '../../core/injection_config.dart';
import 'remote_control_screen.dart';

// ─── Brand Colours ─────────────────────────────────────────────────────────
const _navy        = Color(0xFF003366);
const _navyMid     = Color(0xFF004080);
const _navyDark    = Color(0xFF002244);
const _accentBlue  = Color(0xFFA8C4E0);
const _bg          = Color(0xFFF0F4F8);
const _cardBg      = Color(0xFFFFFFFF);
const _cardBorder  = Color(0xFFE2EAF4);
const _textDark    = Color(0xFF003366);
const _textMid     = Color(0xFF8A9BB0);
const _inputBg     = Color(0xFFF8FAFC);
const _inputBorder = Color(0xFF1A2B3C);
// ──────────────────────────────────────────────────────────────────────────────

class LiveDemoSetupScreen extends StatefulWidget {
  const LiveDemoSetupScreen({super.key});

  @override
  State<LiveDemoSetupScreen> createState() => _LiveDemoSetupScreenState();
}

class _LiveDemoSetupScreenState extends State<LiveDemoSetupScreen> {
  final _rosterService      = RosterService();
  final _liveSessionService = LiveSessionService();

  String _searchQuery   = '';
  String _selectedType  = 'IM';

  Stream<List<StudentRoster>>? _rosterStream;
  String? _cachedInstructorId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<UserRoleProvider>().uid;
    if (uid != _cachedInstructorId && uid != null) {
      _cachedInstructorId = uid;
      _rosterStream = _rosterService.watchRoster(uid);
    }
  }

  Future<void> _importRoster(String instructorId) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv'], withData: true);
      if (result != null && result.files.single.bytes != null) {
        await _rosterService.importCsv(instructorId, result.files.single.bytes!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Roster imported successfully!')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing roster: $e')));
      }
    }
  }

  void _startSession(String instructorId, StudentRoster student) async {
    final config = InjectionConfigService.getConfig(_selectedType);
    await _liveSessionService.startSession(
      instructorId:  instructorId,
      studentName:   '${student.firstName} ${student.lastName}',
      studentEmail:  student.email,
      injectionType: _selectedType,
      targetAngle:   config.targetAngle,
    );
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const RemoteControlScreen()));
    }
  }

  // Avatar colour palette keyed by email hash
  Color _avatarColor(String email) {
    const palette = [
      Color(0xFF003366), Color(0xFF0E7490), Color(0xFF1A7A4A),
      Color(0xFF004080), Color(0xFF2D4A6E), Color(0xFFB45309),
    ];
    return palette[email.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<UserRoleProvider>();
    final instructorId = roleProvider.uid;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _buildHeader(instructorId),

            // ── Search + Type selector ───────────────────────────────────────
            Container(
              color: _cardBg,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: _inputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _inputBorder, width: 1.5),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          SvgPicture.string(
                            '<svg width="15" height="15" viewBox="0 0 15 15" fill="none"><circle cx="6.5" cy="6.5" r="4.5" stroke="rgba(74,96,128,0.4)" stroke-width="1.4"/><path d="M10 10l3 3" stroke="rgba(74,96,128,0.4)" stroke-width="1.4" stroke-linecap="round"/></svg>',
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Search student name...',
                                hintStyle: TextStyle(color: _textMid.withValues(alpha: 0.7), fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: const TextStyle(color: _textDark, fontSize: 13),
                              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: _inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _inputBorder, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedType,
                        icon: SvgPicture.string(
                          '<svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M3 4.5l3 3 3-3" stroke="rgba(74,96,128,0.5)" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                        ),
                        style: const TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w700),
                        items: InjectionConfigService.allTypes
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedType = v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Container(color: _cardBg, child: const Divider(color: _cardBorder, height: 1)),

            // ── Body ─────────────────────────────────────────────────────────
            Expanded(
              child: Container(
                color: _cardBg,
                child: Column(
                  children: [
                    // Import hint
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: _navy.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _navy.withValues(alpha: 0.2),
                            width: 1.5,
                            // dashed approximation
                          ),
                        ),
                        child: Row(
                          children: [
                            SvgPicture.string(
                              '<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="6" stroke="#003366" stroke-width="1.3"/><path d="M8 7v4M8 5.5h.01" stroke="#003366" stroke-width="1.3" stroke-linecap="round"/></svg>',
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: RichText(
                                text: const TextSpan(
                                  style: TextStyle(color: _textMid, fontSize: 12),
                                  children: [
                                    TextSpan(text: 'Upload a '),
                                    TextSpan(text: '.csv', style: TextStyle(color: _navy, fontWeight: FontWeight.w600)),
                                    TextSpan(text: ' roster or add students via the '),
                                    TextSpan(text: '+', style: TextStyle(color: _navy, fontWeight: FontWeight.w600)),
                                    TextSpan(text: ' button above.'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Roster list
                    Expanded(
                      child: instructorId == null || _rosterStream == null
                          ? const SizedBox.shrink()
                          : StreamBuilder<List<StudentRoster>>(
                              stream: _rosterStream,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Center(child: CircularProgressIndicator(color: _navy));
                                }
                                var students = snapshot.data ?? [];
                                if (_searchQuery.isNotEmpty) {
                                  students = students
                                      .where((s) =>
                                          s.firstName.toLowerCase().contains(_searchQuery) ||
                                          s.lastName.toLowerCase().contains(_searchQuery))
                                      .toList();
                                }
                                if (students.isEmpty) {
                                  return Center(
                                    child: Text(
                                      'No students found.\nImport a CSV to build your roster.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: _textMid, fontSize: 13),
                                    ),
                                  );
                                }
                                return ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                                  itemCount: students.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final student = students[index];
                                    final initials =
                                        '${student.firstName[0]}${student.lastName[0]}'.toUpperCase();
                                    final target = InjectionConfigService.getConfig(_selectedType)
                                        .targetAngle
                                        .toStringAsFixed(0);

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _cardBg,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: _cardBorder),
                                        boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 2))],
                                      ),
                                      child: Row(
                                        children: [
                                          // Avatar
                                          Container(
                                            width: 44, height: 44,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _avatarColor(student.email),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(initials,
                                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                                          ),
                                          const SizedBox(width: 12),
                                          // Info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${student.firstName} ${student.lastName}',
                                                    style: const TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w700)),
                                                const SizedBox(height: 1),
                                                Text(student.email,
                                                    style: const TextStyle(color: _textMid, fontSize: 11.5)),
                                                const SizedBox(height: 3),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: _navy.withValues(alpha: 0.07),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text('$_selectedType \u00b7 $target\u00b0',
                                                      style: const TextStyle(color: _navy, fontSize: 10, fontWeight: FontWeight.w700)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Start Session button
                                          GestureDetector(
                                            onTap: () => _startSession(instructorId, student),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: _navy,
                                                borderRadius: BorderRadius.circular(10),
                                                boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 4))],
                                              ),
                                              child: const Text('Start Session',
                                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
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

  Widget _buildHeader(String? instructorId) {
    return Container(
      color: _navy,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -30, top: -71,
            child: Container(
              width: 209, height: 207,
              decoration: BoxDecoration(color: _navyMid.withValues(alpha: 0.4), shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: -20, top: 28,
            child: Container(
              width: 153, height: 151,
              decoration: BoxDecoration(color: _navyDark.withValues(alpha: 0.3), shape: BoxShape.circle),
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
                const Expanded(
                  child: Text('Live Demo Setup',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                // Import CSV
                GestureDetector(
                  onTap: () { if (instructorId != null) _importRoster(instructorId); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: _accentBlue.withValues(alpha: 0.5), width: 1.5),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      children: [
                        SvgPicture.string(
                          '<svg width="13" height="13" viewBox="0 0 13 13" fill="none"><path d="M6.5 1v7M4 5l2.5 3L9 5" stroke="#A8C4E0" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/><rect x="1" y="9.5" width="11" height="2.5" rx="1" stroke="#A8C4E0" stroke-width="1.2"/></svg>',
                        ),
                        const SizedBox(width: 5),
                        const Text('Import CSV',
                            style: TextStyle(color: _accentBlue, fontSize: 12, fontWeight: FontWeight.w600)),
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
}
