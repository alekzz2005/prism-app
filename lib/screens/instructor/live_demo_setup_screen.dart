import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/roster_service.dart';
import 'section_detail_screen.dart';

class LiveDemoSetupScreen extends StatefulWidget {
  const LiveDemoSetupScreen({super.key});

  @override
  State<LiveDemoSetupScreen> createState() => _LiveDemoSetupScreenState();
}

class _LiveDemoSetupScreenState extends State<LiveDemoSetupScreen> {
  final _rosterService = RosterService();
  String _searchQuery = '';

  Future<void> _createSection(String instructorId) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Create New Section', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g., N1, N2, N01',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _rosterService.createSection(instructorId, result.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<UserRoleProvider>();
    final instructorId = roleProvider.uid;

    if (instructorId == null) return const Scaffold();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Sections', style: TextStyle(color: Colors.white, fontSize: 16)),
        leading: const BackButton(color: Colors.white54),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add, color: Colors.greenAccent),
            label: const Text('New Section', style: TextStyle(color: Colors.greenAccent)),
            onPressed: () => _createSection(instructorId),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search sections...',
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
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: StreamBuilder<List<String>>(
              stream: _rosterService.watchSections(instructorId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
                }

                var sections = snapshot.data ?? [];

                if (_searchQuery.isNotEmpty) {
                  sections = sections.where((s) => s.toLowerCase().contains(_searchQuery)).toList();
                }

                if (sections.isEmpty) {
                  return const Center(
                    child: Text(
                      'No sections found.\nClick "New Section" to create one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.5,
                  ),
                  itemCount: sections.length,
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SectionDetailScreen(
                              instructorId: instructorId,
                              sectionName: section,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_shared, color: Colors.deepPurpleAccent, size: 32),
                            const SizedBox(height: 12),
                            Text(
                              section,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
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
