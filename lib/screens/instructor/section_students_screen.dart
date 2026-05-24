import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/roster_service.dart';

// ─── Brand Colours ────────────────────────────────────────────────────────────
const _navy = Color(0xFF003366);
const _navyMid = Color(0xFF004080);
const _accentBlue = Color(0xFFA8C4E0);
const _bg = Color(0xFFF8FAFC);
const _cardBg = Color(0xFFFFFFFF);
const _cardBorder = Color(0xFFE2EAF4);
const _textDark = Color(0xFF1A2B3C);
const _textMid = Color(0xFF4A5568);
const _textLight = Color(0xFF8A9BB0);
const _red = Color(0xFF991B1B);
const _redBg = Color(0xFFFEF2F2);
const _redBorder = Color(0xFFFECACA);
const _inputBg = Color(0xFFF8FAFC);
// ─────────────────────────────────────────────────────────────────────────────

class SectionStudentsScreen extends StatefulWidget {
  final String sectionName;
  const SectionStudentsScreen({super.key, required this.sectionName});

  @override
  State<SectionStudentsScreen> createState() => _SectionStudentsScreenState();
}

class _SectionStudentsScreenState extends State<SectionStudentsScreen> {
  final _rosterService = RosterService();
  String _searchQuery = '';

  void _showAddStudentModal(String instructorId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddStudentBottomSheet(
        instructorId: instructorId,
        sectionName: widget.sectionName,
        rosterService: _rosterService,
      ),
    );
  }

  void _confirmArchive(String instructorId, StudentRoster student) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: _redBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: _redBorder, width: 2),
                ),
                child: Center(
                  child: SvgPicture.string(
                    '<svg width="26" height="26" viewBox="0 0 26 26" fill="none"><path d="M4 7h18M9 7V5a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2M19 7l-1 13a2 2 0 0 1-2 2h-6a2 2 0 0 1-2-2L7 7" stroke="#991B1B" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M11 12v5M15 12v5" stroke="#991B1B" stroke-width="1.5" stroke-linecap="round"/></svg>',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Archive Student?', style: TextStyle(color: _textDark, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(color: _textMid, fontSize: 13, height: 1.5),
                  children: [
                    const TextSpan(text: 'This will archive '),
                    TextSpan(text: student.formattedFullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: ' from ${widget.sectionName}. They will no longer appear in the active roster.'),
                  ]
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: _cardBorder, width: 1.5),
                        ),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: _textMid, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archive not fully implemented on backend yet.')));
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: _redBg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: _redBorder, width: 1.5),
                        ),
                      ),
                      child: const Text('Archive', style: TextStyle(color: _red, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Color _avatarColor(String email) {
    const palette = [
      Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFF059669),
      Color(0xFFDC2626), Color(0xFFD97706), Color(0xFF0284C7),
      Color(0xFFB45309), Color(0xFF6D28D9), Color(0xFF065F46),
      Color(0xFF9D174D), Color(0xFF1E40AF),
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
            _buildHeader(),
            _buildSearch(),
            _buildSwipeHint(),
            Expanded(
              child: _buildStudentList(instructorId),
            ),
          ],
        ),
      ),
      floatingActionButton: instructorId == null
          ? null
          : GestureDetector(
              onTap: () => _showAddStudentModal(instructorId),
              child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: _navy,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.38), blurRadius: 24, offset: const Offset(0, 6))],
                ),
                child: Center(
                  child: SvgPicture.string(
                    '<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><path d="M11 5v12M5 11h12" stroke="white" stroke-width="2.2" stroke-linecap="round"/></svg>',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
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
                color: const Color(0xFF002244).withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: SvgPicture.string(
                      '<svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M10 12L5 8 10 4" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PRISM', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.0)),
                    const SizedBox(height: 3),
                    Text(widget.sectionName.toUpperCase(), style: const TextStyle(color: _accentBlue, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: _inputBg,
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
                decoration: const InputDecoration(
                  hintText: 'Search students...',
                  hintStyle: TextStyle(color: _textMid, fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: const TextStyle(color: _textDark, fontSize: 13),
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  setState(() => _searchQuery = '');
                  FocusScope.of(context).unfocus();
                },
                child: Container(
                  width: 18, height: 18,
                  decoration: const BoxDecoration(
                    color: _textMid,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.string(
                    '<svg width="10" height="10" viewBox="0 0 10 10" fill="none"><path d="M2 2l6 6M8 2l-6 6" stroke="white" stroke-width="1.5" stroke-linecap="round"/></svg>',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeHint() {
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.string(
            '<svg width="13" height="13" viewBox="0 0 13 13" fill="none"><path d="M8 6.5H2M2 6.5L4.5 4M2 6.5L4.5 9" stroke="#8A9BB0" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/><path d="M11 6.5H9.5" stroke="#8A9BB0" stroke-width="1.3" stroke-linecap="round"/></svg>',
          ),
          const SizedBox(width: 4),
          const Text('Swipe left to archive', style: TextStyle(color: _textMid, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStudentList(String? instructorId) {
    if (instructorId == null) return const SizedBox.shrink();

    return StreamBuilder<List<StudentRoster>>(
      stream: _rosterService.watchRoster(instructorId, widget.sectionName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _navy));
        }

        var students = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          students = students.where((s) =>
            s.formattedFullName.toLowerCase().contains(_searchQuery) ||
            s.email.toLowerCase().contains(_searchQuery)
          ).toList();
        }

        if (students.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: 0.35,
                  child: SvgPicture.string(
                    '<svg width="40" height="40" viewBox="0 0 40 40" fill="none"><circle cx="20" cy="16" r="8" stroke="#8A9BB0" stroke-width="2"/><path d="M6 36c0-7.732 6.268-14 14-14s14 6.268 14 14" stroke="#8A9BB0" stroke-width="2" stroke-linecap="round"/></svg>',
                  ),
                ),
                const SizedBox(height: 10),
                const Text('No students yet', style: TextStyle(color: _textMid, fontSize: 14, fontWeight: FontWeight.w500)),
                const Text('Tap + to add a student', style: TextStyle(color: _textMid, fontSize: 12)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: students.length,
          itemBuilder: (context, i) => _buildStudentCard(students[i], instructorId),
        );
      },
    );
  }

  Widget _buildStudentCard(StudentRoster student, String instructorId) {
    final c = _avatarColor(student.email);
    final initials = student.firstName.isNotEmpty ? student.firstName[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(student.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: _redBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _redBorder),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.archive, color: _red, size: 24),
              const SizedBox(height: 3),
              const Text('Archive', style: TextStyle(color: _red, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        confirmDismiss: (direction) async {
          _confirmArchive(instructorId, student);
          return false;
        },
        child: Container(
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
            boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student.formattedFullName, style: const TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text(student.email, style: const TextStyle(color: _textMid, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Add Student Bottom Sheet ───────────────────────────────────────────────────
class _AddStudentBottomSheet extends StatefulWidget {
  final String instructorId;
  final String sectionName;
  final RosterService rosterService;

  const _AddStudentBottomSheet({
    required this.instructorId,
    required this.sectionName,
    required this.rosterService,
  });

  @override
  State<_AddStudentBottomSheet> createState() => _AddStudentBottomSheetState();
}

class _AddStudentBottomSheetState extends State<_AddStudentBottomSheet> {
  final _firstCtrl = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _middleCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    if (first.isEmpty || last.isEmpty) return;

    // Extract first letter of middle name as middle initial
    final middleRaw = _middleCtrl.text.trim();
    final middleInitial = middleRaw.isNotEmpty ? middleRaw[0].toUpperCase() : '';

    // Derive a placeholder email from name so the field stays non-empty
    final email = '${first.toLowerCase()}.${last.toLowerCase()}@prism.edu';

    setState(() => _isLoading = true);
    try {
      await widget.rosterService.addStudent(
        widget.instructorId,
        widget.sectionName,
        firstName: first,
        lastName: last,
        middleInitial: middleInitial,
        email: email,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding student: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: _cardBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // Title row
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: _navy.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                    child: Center(
                      child: SvgPicture.string(
                        '<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><circle cx="11" cy="8" r="4" stroke="#003366" stroke-width="1.7"/><path d="M3 20c0-4.418 3.582-8 8-8s8 3.582 8 8" stroke="#003366" stroke-width="1.7" stroke-linecap="round"/></svg>',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Add Student', style: TextStyle(color: _textDark, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Fill in the student\'s name details', style: TextStyle(color: _textMid, fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // First Name
              _fieldLabel('FIRST NAME'),
              _inputField(_firstCtrl, 'e.g. Juan'),
              const SizedBox(height: 14),

              // Middle Name
              _fieldLabel('MIDDLE NAME'),
              _inputField(_middleCtrl, 'e.g. Dela Cruz (optional)'),
              const SizedBox(height: 4),
              const Text('Only the first letter will be saved as the middle initial.', style: TextStyle(color: _textMid, fontSize: 10)),
              const SizedBox(height: 14),

              // Last Name
              _fieldLabel('LAST NAME'),
              _inputField(_lastCtrl, 'e.g. Santos'),
              const SizedBox(height: 24),

              // Submit
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Add Student', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: _cardBorder, width: 1.5),
                  ),
                ),
                child: const Text('Cancel', style: TextStyle(color: _textMid, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(label, style: const TextStyle(color: _navy, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
  );

  Widget _inputField(TextEditingController ctrl, String hint) => Container(
    height: 46,
    decoration: BoxDecoration(
      color: _inputBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _cardBorder, width: 1.5),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    alignment: Alignment.centerLeft,
    child: TextField(
      controller: ctrl,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _textMid, fontSize: 13),
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      style: const TextStyle(color: _textDark, fontSize: 13),
    ),
  );
}
