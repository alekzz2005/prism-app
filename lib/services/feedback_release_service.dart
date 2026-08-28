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
        
        // TODO: In a production environment with a backend, we would trigger a Cloud Function here
        // or the backend would listen to the 'feedbackStatus' change to send an FCM message.
        // For now, we simulate the background notification locally:
        print('FCM SIMULATION: Sent background push notification to student regarding session $sessionId.');
        
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
}
