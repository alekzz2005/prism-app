import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/session_model.dart';
import 'session_detail_screen.dart';

/// Student Dashboard
/// Lists all sessions for the logged-in student, organised by injection type tabs.
/// Shows both pending and released feedback.
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

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('My Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.deepPurpleAccent,
          labelColor: Colors.deepPurpleAccent,
          unselectedLabelColor: Colors.white54,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Not signed in.', style: TextStyle(color: Colors.white54)))
          : TabBarView(
              controller: _tabController,
              children: _tabs.map((type) => _SessionList(uid: uid, typeFilter: type)).toList(),
            ),
    );
  }
}

class _SessionList extends StatelessWidget {
  final String uid;
  final String typeFilter;

  const _SessionList({required this.uid, required this.typeFilter});

  Stream<QuerySnapshot> _buildQuery() {
    return FirebaseFirestore.instance
        .collection('sessions')
        .where('userId', isEqualTo: uid)
        // Removed feedbackStatus filter to show both pending and released
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildQuery(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
        }
        
        final docs = snap.data?.docs ?? [];
        final sessions = docs
            .map(SessionModel.fromFirestore)
            .where((s) => s.injectionType == typeFilter)
            .toList();

        if (sessions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No $typeFilter sessions found.\nWait for your instructor to start a demo.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, height: 1.6),
              ),
            ),
          );
        }
        
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sessions.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _SessionTile(session: sessions[index]),
        );
      },
    );
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
    final isReleased = session.feedbackStatus == 'Released';

    return GestureDetector(
      key: Key('session_tile_${session.sessionId}'),
      onTap: () {
        if (isReleased) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SessionDetailScreen(session: session)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This session is still pending instructor review. Please wait.')),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isReleased 
                  ? Colors.deepPurpleAccent.withValues(alpha: 0.3) 
                  : Colors.orangeAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Score circle or Pending Icon
            if (isReleased)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _scoreColor(session.overallScore).withValues(alpha: 0.15),
                  border: Border.all(color: _scoreColor(session.overallScore), width: 2),
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
              )
            else
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orangeAccent.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.orangeAccent, width: 2),
                ),
                child: const Center(
                  child: Icon(Icons.pending_actions, color: Colors.orangeAccent),
                ),
              ),
              
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(session.injectionType,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isReleased ? Colors.greenAccent.withValues(alpha: 0.2) : Colors.orangeAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isReleased ? 'Released' : 'Pending',
                          style: TextStyle(
                            color: isReleased ? Colors.greenAccent : Colors.orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(formatted, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            Icon(isReleased ? Icons.chevron_right : Icons.lock_clock, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
