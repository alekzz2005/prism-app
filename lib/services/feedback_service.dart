import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/session_state_provider.dart';
import '../core/injection_config.dart';
import 'openrouter_api_client.dart';
import 'feedback_exceptions.dart';

/// Builds the LLM prompt from live session state.
class PayloadBuilder {
  static String buildPrompt(SessionStateProvider session) {
    final config = session.currentConfig;
    final type = config?.type ?? 'Unknown';
    final target = config?.targetAngle.toStringAsFixed(0) ?? '?';

    return '''Student completed a $type injection return demonstration.
Insertion angle: ${session.insertionAngle?.toStringAsFixed(1) ?? '?'}° (target: $target°, score: ${session.insertionScore ?? '?'}/5)
Aspiration: ${session.aspirationResult ?? 'Not Detected'} (duration: ${session.aspirationDuration?.toStringAsFixed(1) ?? '0'}s, smoothness: ${session.motionSmoothness ?? 'Unknown'})
Withdrawal angle: ${session.withdrawalAngle?.toStringAsFixed(1) ?? '?'}° (delta from insertion: ${session.angularDelta?.toStringAsFixed(1) ?? '?'}°, result: ${session.correspondenceResult ?? 'Unknown'}, score: ${session.withdrawalScore ?? '?'}/5)
Overall score: ${session.overallScore ?? '?'}/5
Generate clinical feedback for this student.''';
  }
}

/// Orchestrates AI feedback generation and Firestore session persistence.
class FeedbackService {
  final _client = OpenRouterApiClient();
  final _db = FirebaseFirestore.instance;

  /// Builds prompt, calls OpenRouter, writes to Firestore.
  /// Returns the generated sessionId.
  Future<String> submitSession(
      SessionStateProvider session, String userId) async {
    final prompt = PayloadBuilder.buildPrompt(session);
    String feedbackText = '';
    String feedbackStatus = 'Pending';

    try {
      feedbackText = await _client.generateFeedback(prompt);
    } on FeedbackTimeoutException {
      feedbackText = '';
      feedbackStatus = 'Feedback Generation Failed';
    } on FeedbackApiException {
      feedbackText = '';
      feedbackStatus = 'Feedback Generation Failed';
    }

    final doc = await _db.collection('sessions').add({
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
      'injectionType': session.currentConfig?.type ?? '',
      'insertionAngle': session.insertionAngle ?? 0.0,
      'insertionScore': session.insertionScore ?? 1,
      'aspirationResult': session.aspirationResult ?? 'Not Detected',
      'aspirationDuration': session.aspirationDuration ?? 0.0,
      'motionSmoothness': session.motionSmoothness ?? 'Good',
      'withdrawalAngle': session.withdrawalAngle ?? 0.0,
      'withdrawalScore': session.withdrawalScore ?? 1,
      'correspondenceResult': session.correspondenceResult ?? 'Deviates',
      'angularDelta': session.angularDelta ?? 0.0,
      'overallScore': session.overallScore ?? 1,
      'aiFeedbackText': feedbackText,
      'feedbackStatus': feedbackStatus,
      'releaseTimestamp': null,
      'instructorNote': '',
      'flagged': session.flagged,
    });

    return doc.id;
  }
}
