import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/session_model.dart';

/// Firestore read operations for the Instructor role.
class InstructorSessionRepository {
  final _db = FirebaseFirestore.instance;

  /// Streams all sessions ordered by timestamp descending.
  /// Optional [statusFilter], [typeFilter], and [sectionFilter] narrow the query.
  Stream<List<SessionModel>> watchAllSessions({
    String? statusFilter,
    String? typeFilter,
    String? sectionFilter,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('sessions')
        .orderBy('timestamp', descending: true);

    if (statusFilter != null) {
      query = query.where('feedbackStatus', isEqualTo: statusFilter);
    }
    if (typeFilter != null) {
      query = query.where('injectionType', isEqualTo: typeFilter);
    }
    if (sectionFilter != null) {
      query = query.where('sectionName', isEqualTo: sectionFilter);
    }

    return query.snapshots().map(
          (snap) => snap.docs
              .map(SessionModel.fromFirestore)
              .where((s) => s.sectionName != 'Practice' && s.partnerName != 'Self-Practice')
              .toList(),
        );
  }

  /// Saves a new session document and returns the auto-generated ID.
  Future<String> saveSession(SessionModel session) async {
    final ref =
        await _db.collection('sessions').add(session.toFirestore());
    return ref.id;
  }

  /// Updates a draft session with the edited feedback.
  Future<void> updateFeedbackDraft(String sessionId, String noteText) async {
    await _db.collection('sessions').doc(sessionId).update({
      'instructorNote': noteText,
    });
  }
}
