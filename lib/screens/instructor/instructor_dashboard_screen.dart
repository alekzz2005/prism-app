import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/session_model.dart';
import '../../providers/user_role_provider.dart';
import '../../services/auth_service.dart';
import '../../services/instructor_session_repository.dart';
import '../../widgets/auth_wrapper.dart';
import 'feedback_review_screen.dart';
import 'camera_node_screen.dart';
import 'live_demo_setup_screen.dart';

/// UC-4.1 — Instructor dashboard with filter chips.
class InstructorDashboardScreen extends StatefulWidget {
  const InstructorDashboardScreen({super.key});

  @override
  State<InstructorDashboardScreen> createState() =>
      _InstructorDashboardScreenState();
}

class _InstructorDashboardScreenState
    extends State<InstructorDashboardScreen> {
  final _repo = InstructorSessionRepository();

  String _statusFilter = 'All';
  String _typeFilter = 'All';

  static const _statusOptions = ['All', 'Pending', 'Released'];
  static const _typeOptions = ['All', 'IM', 'SubQ', 'IV', 'ID'];

  List<SessionModel> _applyFilters(List<SessionModel> sessions) {
    return sessions.where((s) {
      final matchStatus =
          _statusFilter == 'All' || s.feedbackStatus == _statusFilter;
      final matchType =
          _typeFilter == 'All' || s.injectionType == _typeFilter;
      return matchStatus && matchType;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<UserRoleProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Instructor Dashboard',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            Text(roleProvider.fullName ?? '',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('instructor_signout'),
            icon: const Icon(Icons.logout, color: Colors.white54),
            onPressed: () async {
              await AuthService().signOut();
              if (!context.mounted) return;
              roleProvider.clear();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AuthWrapper()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Mode Selection Area ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    label: const Text('Camera Mode\n(Tripod)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraNodeScreen()));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.deepPurpleAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.co_present, color: Colors.white),
                    label: const Text('Live Demo\n(Remote)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveDemoSetupScreen()));
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          
          // ── Session History Header ──
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Past Sessions',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // ── Status filter chips ──
          _FilterRow(
            label: 'Status',
            options: _statusOptions,
            selected: _statusFilter,
            onSelected: (v) => setState(() => _statusFilter = v),
          ),
          // ── Type filter chips ──
          _FilterRow(
            label: 'Type',
            options: _typeOptions,
            selected: _typeFilter,
            onSelected: (v) => setState(() => _typeFilter = v),
          ),
          const Divider(color: Colors.white12, height: 1),

          // ── Session list ──
          Expanded(
            child: StreamBuilder<List<SessionModel>>(
              stream: _repo.watchAllSessions(
                statusFilter:
                    _statusFilter == 'All' ? null : _statusFilter,
                typeFilter:
                    _typeFilter == 'All' ? null : _typeFilter,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: Colors.deepPurpleAccent));
                }
                final sessions = _applyFilters(snap.data ?? []);
                if (sessions.isEmpty) {
                  return const Center(
                    child: Text('No sessions match the current filters.',
                        style: TextStyle(color: Colors.white54)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _SessionCard(session: sessions[index], repo: _repo),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _FilterRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12)),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: options.map((opt) {
                    final active = opt == selected;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(opt),
                        selected: active,
                        onSelected: (_) => onSelected(opt),
                        selectedColor: Colors.deepPurpleAccent,
                        backgroundColor: const Color(0xFF1A1A2E),
                        labelStyle: TextStyle(
                          color: active ? Colors.white : Colors.white54,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        side: BorderSide(
                          color: active
                              ? Colors.deepPurpleAccent
                              : Colors.white24,
                        ),
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

class _SessionCard extends StatelessWidget {
  final SessionModel session;
  final InstructorSessionRepository repo;

  const _SessionCard({required this.session, required this.repo});

  Color _statusColor(String status) {
    if (status == 'Released') return Colors.greenAccent;
    if (status == 'Pending') return Colors.amberAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final date = session.timestamp.toDate();
    return GestureDetector(
      key: Key('instructor_session_${session.sessionId}'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              FeedbackReviewScreen(session: session, repo: repo),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            // Score circle
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.deepPurple.withValues(alpha: 0.2),
              ),
              child: Center(
                child: Text('${session.overallScore}',
                    style: const TextStyle(
                        color: Colors.deepPurpleAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
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
                      Text(session.injectionType,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor(session.feedbackStatus)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(session.feedbackStatus,
                            style: TextStyle(
                                color:
                                    _statusColor(session.feedbackStatus),
                                fontSize: 10)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}/${date.month}/${date.year}  •  ${session.userId.substring(0, 8)}…',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
