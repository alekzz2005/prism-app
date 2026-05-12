import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/session_model.dart';
import 'session_detail_screen.dart';

/// UC-3.3 — Lists released sessions for the logged-in student.
class MySessionsScreen extends StatefulWidget {
  const MySessionsScreen({super.key});

  @override
  State<MySessionsScreen> createState() => _MySessionsScreenState();
}

class _MySessionsScreenState extends State<MySessionsScreen> {
  String _typeFilter = 'All';
  static const _typeOptions = ['All', 'IM', 'SubQ', 'IV', 'ID'];

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('My Sessions',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: uid == null
          ? const Center(
              child: Text('Not signed in.',
                  style: TextStyle(color: Colors.white54)))
          : Column(
              children: [
                // ── Type filter chips ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _typeOptions.map((opt) {
                        final active = opt == _typeFilter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(opt),
                            selected: active,
                            onSelected: (_) =>
                                setState(() => _typeFilter = opt),
                            selectedColor: Colors.deepPurpleAccent,
                            backgroundColor: const Color(0xFF1A1A2E),
                            labelStyle: TextStyle(
                              color: active
                                  ? Colors.white
                                  : Colors.white54,
                              fontSize: 13,
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
                const Divider(color: Colors.white12, height: 1),

                // ── Session list ──
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _buildQuery(uid),
                    builder: (context, snap) {
                      if (snap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: Colors.deepPurpleAccent));
                      }
                      final docs = snap.data?.docs ?? [];
                      final sessions = docs
                          .map(SessionModel.fromFirestore)
                          .where((s) =>
                              _typeFilter == 'All' ||
                              s.injectionType == _typeFilter)
                          .toList();

                      if (sessions.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No released sessions yet.\nComplete a return-demonstration to see feedback here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white54, height: 1.6),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: sessions.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _SessionTile(session: sessions[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Stream<QuerySnapshot> _buildQuery(String uid) {
    return FirebaseFirestore.instance
        .collection('sessions')
        .where('userId', isEqualTo: uid)
        .where('feedbackStatus', isEqualTo: 'Released')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}

class _SessionTile extends StatelessWidget {
  final SessionModel session;
  const _SessionTile({required this.session});

  Color _scoreColor(int s) {
    if (s >= 4) return Colors.greenAccent;
    if (s == 3) return Colors.amberAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final date = session.timestamp.toDate();
    final formatted = DateFormat('MMM d, y  h:mm a').format(date);

    return GestureDetector(
      key: Key('session_tile_${session.sessionId}'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                SessionDetailScreen(session: session)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Score circle
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _scoreColor(session.overallScore)
                    .withValues(alpha: 0.15),
                border: Border.all(
                    color: _scoreColor(session.overallScore), width: 2),
              ),
              child: Center(
                child: Text(
                  '${session.overallScore}/5',
                  style: TextStyle(
                      color: _scoreColor(session.overallScore),
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.injectionType,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(formatted,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
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
