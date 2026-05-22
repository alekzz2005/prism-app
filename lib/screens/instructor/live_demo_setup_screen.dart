import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/roster_service.dart';
import '../../services/live_session_service.dart';
import '../../core/injection_config.dart';
import 'remote_control_screen.dart';

class LiveDemoSetupScreen extends StatefulWidget {
  const LiveDemoSetupScreen({super.key});

  @override
  State<LiveDemoSetupScreen> createState() => _LiveDemoSetupScreenState();
}

class _LiveDemoSetupScreenState extends State<LiveDemoSetupScreen> {
  final _rosterService = RosterService();
  final _liveSessionService = LiveSessionService();

  String _searchQuery = '';
  String _selectedType = 'IM';

  Future<void> _importRoster(String instructorId) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        await _rosterService.importCsv(instructorId, result.files.single.bytes!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Roster imported successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing roster: $e')),
        );
      }
    }
  }

  void _startSession(String instructorId, StudentRoster student) async {
    final config = InjectionConfigService.getConfig(_selectedType);
    
    await _liveSessionService.startSession(
      instructorId: instructorId,
      studentName: '${student.firstName} ${student.lastName}',
      studentEmail: student.email,
      injectionType: _selectedType,
      targetAngle: config.targetAngle,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RemoteControlScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<UserRoleProvider>();
    final instructorId = roleProvider.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Live Demo Setup', style: TextStyle(color: Colors.white, fontSize: 16)),
        leading: const BackButton(color: Colors.white54),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.greenAccent),
            tooltip: 'Add Mock Student',
            onPressed: () async {
              await _rosterService.addMockStudent(instructorId!);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mock student added!')),
                );
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.upload_file, color: Colors.deepPurpleAccent),
            label: const Text('Import CSV', style: TextStyle(color: Colors.deepPurpleAccent)),
            onPressed: () => _importRoster(instructorId!),
          ),
        ],
      ),
      body: Column(
        children: [
          // Settings Area
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search student name...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedType,
                    dropdownColor: const Color(0xFF1A1A2E),
                    underline: const SizedBox(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    items: InjectionConfigService.allTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedType = v);
                    },
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(color: Colors.white12, height: 1),

          // Roster List
          Expanded(
            child: StreamBuilder<List<StudentRoster>>(
              stream: _rosterService.watchRoster(instructorId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
                }

                var students = snapshot.data ?? [];
                
                if (_searchQuery.isNotEmpty) {
                  students = students.where((s) =>
                      s.firstName.toLowerCase().contains(_searchQuery) ||
                      s.lastName.toLowerCase().contains(_searchQuery)).toList();
                }

                if (students.isEmpty) {
                  return const Center(
                    child: Text(
                      'No students found.\nImport a CSV to build your roster.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: students.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final student = students[index];
                    return ListTile(
                      tileColor: const Color(0xFF1A1A2E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text('${student.firstName} ${student.lastName}', style: const TextStyle(color: Colors.white)),
                      subtitle: Text(student.email, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurpleAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _startSession(instructorId, student),
                        child: const Text('Start Session', style: TextStyle(color: Colors.white)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
