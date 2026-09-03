import 'package:cloud_firestore/cloud_firestore.dart';

/// Thrown when both release attempts fail.
class ReleaseFailedException implements Exception {
  final String message;
  const ReleaseFailedException(this.message);
  @override
  String toString() => message;
}

/// Atomically updates a session document to release feedback to the student.
/// NEVER modifies aiFeedbackText.
class FeedbackReleaseService {
  final _db = FirebaseFirestore.instance;

  Future<void> releaseSession(
      String sessionId, String instructorNote, String aiFeedbackText) async {
    Exception? lastError;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await _db.collection('sessions').doc(sessionId).update({
          'feedbackStatus': 'Released',
          'releaseTimestamp': FieldValue.serverTimestamp(),
          'instructorNote': instructorNote,
          'aiFeedbackText': aiFeedbackText,
        });
        
        final sessionSnap = await _db.collection('sessions').doc(sessionId).get();
        final sessionData = sessionSnap.data();
        final userId = sessionData?['userId'] as String? ?? '';
        final injectionType = sessionData?['injectionType'] as String? ?? 'IM';
        
        if (userId.isNotEmpty) {
          // Calculate student's official session number
          int sessionNum = 1;
          try {
            final studentSessionsSnap = await _db.collection('sessions')
                .where('userId', isEqualTo: userId)
                .get();
            final officialSessions = studentSessionsSnap.docs
                .where((d) => (d.data()['sectionName'] ?? '') != 'Practice')
                .toList();
            officialSessions.sort((a, b) {
              final aTs = a.data()['timestamp'] as Timestamp?;
              final bTs = b.data()['timestamp'] as Timestamp?;
              if (aTs == null || bTs == null) return 0;
              return aTs.compareTo(bTs);
            });
            final idx = officialSessions.indexWhere((d) => d.id == sessionId);
            if (idx != -1) sessionNum = idx + 1;
          } catch (_) {}

          // Look up user doc to find uid if userId was stored as email
          String targetUid = userId;
          if (userId.contains('@')) {
            final userQuery = await _db.collection('users').where('email', isEqualTo: userId).limit(1).get();
            if (userQuery.docs.isNotEmpty) {
              targetUid = userQuery.docs.first.id;
            }
          }
          
          await _db.collection('users').doc(targetUid).collection('notifications').add({
            'userId': targetUid,
            'title': 'Official RD #$sessionNum Feedback Released',
            'body': 'Your instructor has reviewed and released feedback for your $injectionType Return-Demonstration (Session #$sessionNum).',
            'type': 'feedback_released',
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'relatedSessionId': sessionId,
          });
        }
        
        return;
      } catch (e) {
        lastError = e as Exception;
        if (attempt == 0) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
    throw ReleaseFailedException(lastError.toString());
  }

  Future<int> batchReleaseBySection(String sectionName) async {
    final pendingSessions = await _db.collection('sessions')
        .where('sectionName', isEqualTo: sectionName)
        .where('feedbackStatus', isEqualTo: 'Pending')
        .get();
        
    if (pendingSessions.docs.isEmpty) return 0;
    
    final batch = _db.batch();
    for (var doc in pendingSessions.docs) {
      batch.update(doc.reference, {
        'feedbackStatus': 'Released',
        'releaseTimestamp': FieldValue.serverTimestamp(),
      });
    }
    
    await batch.commit();
    return pendingSessions.docs.length;
  }

  Future<int> batchReleaseByCount(int count) async {
    final pendingSessions = await _db.collection('sessions')
        .where('feedbackStatus', isEqualTo: 'Pending')
        .limit(count)
        .get();
        
    if (pendingSessions.docs.isEmpty) return 0;
    
    final batch = _db.batch();
    for (var doc in pendingSessions.docs) {
      batch.update(doc.reference, {
        'feedbackStatus': 'Released',
        'releaseTimestamp': FieldValue.serverTimestamp(),
      });
    }
    
    await batch.commit();
    return pendingSessions.docs.length;
  }

  Future<int> batchReleaseByIds(List<String> sessionIds) async {
    if (sessionIds.isEmpty) return 0;
    
    final batch = _db.batch();
    for (var id in sessionIds) {
      batch.update(_db.collection('sessions').doc(id), {
        'feedbackStatus': 'Released',
        'releaseTimestamp': FieldValue.serverTimestamp(),
      });
    }
    
    await batch.commit();
    return sessionIds.length;
  }
}
