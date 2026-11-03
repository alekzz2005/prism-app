import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/session_model.dart';

/// Firestore read/write operations for sessions and instructor-only private notes.
class InstructorSessionRepository {
  static const String privateCollectionName = 'private';
  static const String instructorNoteDocId = 'instructor_note';

  final FirebaseFirestore? _firestore;

  InstructorSessionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Reference to the instructor-only document storing the private note for [sessionId].
  DocumentReference<Map<String, dynamic>> privateNoteRef(String sessionId) =>
      _db
          .collection('sessions')
          .doc(sessionId)
          .collection(privateCollectionName)
          .doc(instructorNoteDocId);

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
              .where((s) =>
                  s.sectionName != 'Practice' &&
                  s.partnerName != 'Self-Practice')
              .toList(),
        );
  }

  /// Saves a new session document and returns the auto-generated ID.
  /// Public `sessions/{sessionId}` documents never store a non-empty `instructorNote`.
  /// For official instructor sessions with an initial note (e.g. bleeding-stopped sessions),
  /// the private note is written to `sessions/{sessionId}/private/instructor_note`.
  Future<String> saveSession(SessionModel session) async {
    final ref = await _db.collection('sessions').add(session.toFirestore());
    if (!session.isPractice && session.instructorNote.trim().isNotEmpty) {
      await privateNoteRef(ref.id).set(
        session.toPrivateNoteFirestore(),
        SetOptions(merge: true),
      );
    }
    return ref.id;
  }

  /// Fetches the private instructor note from `sessions/{sessionId}/private/instructor_note`,
  /// falling back to [fallback] (e.g. legacy unmigrated note in memory) if not yet migrated.
  Future<String> fetchInstructorNote(
    String sessionId, {
    String fallback = '',
  }) async {
    if (sessionId.isEmpty) return fallback;
    try {
      final snap = await privateNoteRef(sessionId).get();
      if (snap.exists) {
        final note = snap.data()?['instructorNote'] as String?;
        if (note != null) return note;
      }
    } catch (_) {
      // Fall back to legacy note if offline or not yet created
    }
    return fallback;
  }

  /// Streams the private instructor note from `sessions/{sessionId}/private/instructor_note`.
  Stream<String> watchInstructorNote(
    String sessionId, {
    String fallback = '',
  }) {
    if (sessionId.isEmpty) return Stream.value(fallback);
    return privateNoteRef(sessionId).snapshots().map((snap) {
      if (snap.exists) {
        final note = snap.data()?['instructorNote'] as String?;
        if (note != null) return note;
      }
      return fallback;
    });
  }

  /// Updates a draft session: stores [noteText] in the instructor-only
  /// `sessions/{sessionId}/private/instructor_note` subcollection document and
  /// updates [aiFeedbackText] (while scrubbing any legacy `instructorNote`) on `sessions/{sessionId}`.
  Future<void> updateFeedbackDraft(
    String sessionId,
    String noteText, {
    String? aiFeedbackText,
  }) async {
    final batch = _db.batch();
    batch.set(
      privateNoteRef(sessionId),
      {
        'instructorNote': noteText,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    final sessionUpdate = <String, dynamic>{
      'instructorNote': '',
      'aiFeedbackText': ?aiFeedbackText,
    };
    batch.update(_db.collection('sessions').doc(sessionId), sessionUpdate);
    await batch.commit();
  }

  /// Safe migration utility for historical sessions:
  /// Moves any non-empty `instructorNote` stored directly on `sessions/{sessionId}`
  /// into `sessions/{sessionId}/private/instructor_note` and clears the public field
  /// in atomic batches so private notes are never exposed to students.
  Future<int> migrateLegacyInstructorNotes() async {
    final sessionsSnap = await _db.collection('sessions').get();
    int migratedCount = 0;
    WriteBatch batch = _db.batch();
    int opsInBatch = 0;
    int sessionsInBatch = 0;

    for (final doc in sessionsSnap.docs) {
      final data = doc.data();
      final legacyNote = (data['instructorNote'] as String? ?? '');
      if (legacyNote.isEmpty) continue;

      final privRef = privateNoteRef(doc.id);
      final existingPriv = await privRef.get();
      final existingNote = existingPriv.data()?['instructorNote'] as String?;

      if ((existingNote == null || existingNote.trim().isEmpty) &&
          legacyNote.trim().isNotEmpty) {
        batch.set(
          privRef,
          {
            'instructorNote': legacyNote,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        opsInBatch++;
      }

      batch.update(doc.reference, {'instructorNote': ''});
      opsInBatch++;
      sessionsInBatch++;

      // Firestore WriteBatch limit is 500 operations
      if (opsInBatch >= 400) {
        await batch.commit();
        migratedCount += sessionsInBatch;
        batch = _db.batch();
        opsInBatch = 0;
        sessionsInBatch = 0;
      }
    }

    if (opsInBatch > 0) {
      await batch.commit();
      migratedCount += sessionsInBatch;
    }
    return migratedCount;
  }
}
