import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';

import '../../core/injection_config.dart';
import '../../providers/user_role_provider.dart';
import '../../services/roster_service.dart';
import '../../services/live_session_service.dart';
import 'remote_control_screen.dart';

const _navy = Color(0xFF003366);
const _bg = Color(0xFFF8FAFC);
const _cardBg = Colors.white;
const _cardBorder = Color(0xFFE2E8F0);
const _textDark = Color(0xFF1E293B);
const _textMid = Color(0xFF64748B);
const _inputBg = Color(0xFFF1F5F9);
const _inputBorder = Color(0xFFCBD5E1);
const _accent = Color(0xFF0EA5E9);

class LiveDemoSetupScreen extends StatefulWidget {
  const LiveDemoSetupScreen({Key? key}) : super(key: key);

  @override
  State<LiveDemoSetupScreen> createState() => _LiveDemoSetupScreenState();
}

class _LiveDemoSetupScreenState extends State<LiveDemoSetupScreen> {
  final _rosterService = RosterService();
  final _liveSessionService = LiveSessionService();

  String _selectedType = 'IM';
  String _searchQuery = '';
  
  String? _cachedInstructorId;
  String? _selectedSection;
  Stream<List<String>>? _sectionsStream;
  Stream<List<StudentRoster>>? _rosterStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<UserRoleProvider>().uid;
    if (uid != _cachedInstructorId && uid != null) {
      _cachedInstructorId = uid;
      _sectionsStream = _rosterService.watchSections(uid);
    }
  }
  
  void _selectSection(String section) {
    setState(() {
      _selectedSection = section;
      _rosterStream = _rosterService.watchRoster(_cachedInstructorId!, section);
    });
  }

  Future<void> _createSection(String instructorId) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Section', style: TextStyle(color: _navy)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'e.g. BSN-3A',
            hintStyle: const TextStyle(color: _textMid),
            filled: true,
            fillColor: _inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Cancel', style: TextStyle(color: _textMid))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(context, controller.text.trim()), 
            child: const Text('Create', style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
    
    if (name != null && name.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('instructor_roster')
          .doc(instructorId)
          .collection('sections')
          .doc(name)
          .set({'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
  }

  Future<void> _importRoster(String instructorId) async {
    if (_selectedSection == null) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv', 'xlsx', 'xls'], withData: true);
      if (result != null && result.files.single.bytes != null) {
        await _rosterService.importRoster(instructorId, _selectedSection!, result.files.single.bytes!, result.files.single.name);
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

  void _startSession(String instructorId, StudentRoster student) {
    final config = InjectionConfigService.getConfig(_selectedType);
    
    // Fire and forget so we don't block the UI
    _liveSessionService.startSession(
      instructorId:  instructorId,
      studentName:   '${student.firstName} ${student.lastName}',
      studentEmail:  student.email,
      injectionType: _selectedType,
      targetAngle:   config.targetAngle,
    );
    
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RemoteControlScreen()));
  }

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
            _buildHeader(instructorId),
            
            if (_selectedSection != null)
              _buildSearchAndTypeRow(),
              
            if (_selectedSection != null)
              Container(color: _cardBg, child: const Divider(color: _cardBorder, height: 1)),

            Expanded(
              child: Container(
                color: _cardBg,
                child: _selectedSection == null 
                    ? _buildSectionsList(instructorId)
                    : _buildStudentsList(instructorId),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedSection == null && instructorId != null
          ? FloatingActionButton.extended(
              onPressed: () => _createSection(instructorId),
              backgroundColor: _navy,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('New Section', style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }

  Widget _buildSectionsList(String? instructorId) {
    if (instructorId == null || _sectionsStream == null) return const SizedBox.shrink();
    
    return StreamBuilder<List<String>>(
      stream: _sectionsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _navy));
        }
        final sections = snapshot.data ?? [];
        if (sections.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 64, color: _textMid.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                const Text(
                  'No sections created yet.\nTap "New Section" to get started.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textMid, fontSize: 14),
                ),
              ],
            ),
          );
        }
        
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final section = sections[index];
            return InkWell(
              onTap: () => _selectSection(section),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _cardBorder),
                  boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _navy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.folder, color: _navy),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        section,
                        style: const TextStyle(color: _textDark, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: _textMid),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStudentsList(String? instructorId) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: InkWell(
            onTap: () => _importRoster(instructorId!),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _navy.withValues(alpha: 0.2),
                  width: 1.5,
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
                          TextSpan(text: 'Tap here to upload a '),
                          TextSpan(text: '.csv/.xlsx', style: TextStyle(color: _navy, fontWeight: FontWeight.w600)),
                          TextSpan(text: ' roster to this section.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

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
                          'No students found in $_selectedSection.\nImport a CSV/XLSX to build your roster.',
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
                        final s = students[index];
                        final c = _avatarColor(s.email);
                        final initials = s.firstName.isNotEmpty ? s.firstName[0].toUpperCase() : '?';

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _cardBorder),
                            boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 6, offset: Offset(0, 2))],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _startSession(instructorId, s),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: c.withValues(alpha: 0.15),
                                      child: Text(initials, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(s.formattedFullName, style: const TextStyle(color: _textDark, fontWeight: FontWeight.w600, fontSize: 15)),
                                          const SizedBox(height: 2),
                                          Text(s.email, style: const TextStyle(color: _textMid, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _navy,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: const [BoxShadow(color: Color(0x33003366), blurRadius: 4, offset: Offset(0, 2))],
                                      ),
                                      child: const Text('Select', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchAndTypeRow() {
    return Container(
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
                        hintText: 'Search student...',
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
              decoration: BoxDecoration(
                color: const Color(0xFF0E7490).withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -20, top: 28,
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Row(
              children: [
                if (_selectedSection != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () => setState(() {
                        _selectedSection = null;
                        _rosterStream = null;
                        _searchQuery = '';
                      }),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Demo Setup',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedSection == null 
                            ? 'Select or create a section' 
                            : 'Select a student from $_selectedSection',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                      ),
                    ],
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
