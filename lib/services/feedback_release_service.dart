import 'package:cloud_firestore/cloud_firestore.dart';

/// Thrown when both release attempts fail.
class ReleaseFailedException implements Exception {
  final String message;
  const ReleaseFailedException(this.message);
  @override
  String toString() => 'ReleaseFailedException: $message';
}

/// Atomically updates a session document to release feedback to the student.
/// NEVER modifies aiFeedbackText.
class FeedbackReleaseService {
  final _db = FirebaseFirestore.instance;

  Future<void> releaseSession(
      String sessionId, String instructorNote) async {
    Exception? lastError;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await _db.collection('sessions').doc(sessionId).update({
          'feedbackStatus': 'Released',
          'releaseTimestamp': FieldValue.serverTimestamp(),
          'instructorNote': instructorNote,
          // aiFeedbackText intentionally NOT touched
        });
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
}
