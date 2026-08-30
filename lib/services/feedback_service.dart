import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/session_model.dart';
import '../core/injection_config.dart';
import 'openrouter_api_client.dart';
import 'feedback_exceptions.dart';

/// Builds a compact, structured LLM prompt from the finalized SessionModel.
/// Uses key:value pairs to minimise input tokens while maximising context.
class PayloadBuilder {
  static String buildPrompt(SessionModel session) {
    final config = InjectionConfigService.getConfig(session.injectionType);

    // Injection-specific clinical context from CIT-U rubrics
    final clinicalContext = switch (session.injectionType) {
      'IM' => 'CIT-U Rubric: Intramuscular (IM) Injection Return-Demonstration (Chronological Procedural Evaluation)',
      _ => 'Parenteral Injection Return-Demonstration',
    };

    final aspirationNote = session.aspirationResult == 'Bleeding Detected' || session.aspirationResult == 'Failed (Bleeding)'
        ? 'Blood return detected (Vascular puncture — clinical risk)'
        : 'No blood return (Correct technique — muscle tissue safe)';

    return '$clinicalContext\n'
        'Standard: 90° insertion (±${config.tolerance.toStringAsFixed(0)}° tolerance), 5-10s aspiration check, smooth withdrawal along same vector.\n\n'
        'Step 1 - Insertion Phase:\n'
        '• Target Angle: ${config.targetAngle.toStringAsFixed(0)}° (Tolerance ±${config.tolerance.toStringAsFixed(0)}°)\n'
        '• Measured Angle: ${session.insertionAngle.toStringAsFixed(1)}° (Score: ${session.insertionScore}/5)\n\n'
        'Step 2 - Aspiration Phase:\n'
        '• Aspiration Blood Check: ${session.aspirationResult} ($aspirationNote)\n'
        '• Duration: ${session.aspirationDuration.toStringAsFixed(1)}s\n\n'
        'Step 3 - Withdrawal Phase:\n'
        '• Measured Angle: ${session.withdrawalAngle.toStringAsFixed(1)}° (Score: ${session.withdrawalScore}/5)\n'
        '• Angular Delta: ${session.angularDelta.toStringAsFixed(1)}° (${session.correspondenceResult})\n'
        '• Motion Smoothness: ${session.motionSmoothness}\n\n'
        'Overall Rubric Score: ${session.overallScore}/5'
        '${session.flagged ? '\nFLAGGED: One or more components were undetectable or bleeding was detected.' : ''}';
  }
}

/// Orchestrates AI feedback generation and Firestore session persistence.
class FeedbackService {
  final _client = OpenRouterApiClient();

  /// Builds prompt, calls OpenRouter, and returns a new SessionModel with the AI feedback populated.
  Future<SessionModel> generateFeedbackForSession(SessionModel session) async {
    final prompt = PayloadBuilder.buildPrompt(session);
    String feedbackText = '';
    final isPractice = session.sectionName == 'Practice' || session.partnerName == 'Self-Practice';
    String feedbackStatus = (session.feedbackStatus == 'Released' || isPractice) ? 'Released' : 'Pending';

    String instructorNote = session.instructorNote;

    try {
      feedbackText = await _client.generateFeedback(prompt);
    } on FeedbackTimeoutException catch (e) {
      feedbackText = '';
      feedbackStatus = 'Feedback Generation Failed';
      instructorNote = 'AI Timeout Error: $e';
    } on FeedbackApiException catch (e) {
      feedbackText = '';
      feedbackStatus = 'Feedback Generation Failed';
      instructorNote = 'AI API Error (Code ${e.statusCode}):\n${e.body}';
    } catch (e) {
      feedbackText = '';
      feedbackStatus = 'Feedback Generation Failed';
      instructorNote = 'AI Unknown Error: $e';
    }

    return SessionModel(
      sessionId: session.sessionId,
      userId: session.userId,
      studentName: session.studentName,
      timestamp: session.timestamp,
      injectionType: session.injectionType,
      insertionAngle: session.insertionAngle,
      insertionScore: session.insertionScore,
      aspirationResult: session.aspirationResult,
      aspirationDuration: session.aspirationDuration,
      motionSmoothness: session.motionSmoothness,
      withdrawalAngle: session.withdrawalAngle,
      withdrawalScore: session.withdrawalScore,
      correspondenceResult: session.correspondenceResult,
      angularDelta: session.angularDelta,
      overallScore: session.overallScore,
      aiFeedbackText: feedbackText,
      feedbackStatus: feedbackStatus,
      releaseTimestamp: session.releaseTimestamp,
      instructorNote: instructorNote,
      flagged: session.flagged,
    );
  }

  /// Fire-and-forget background task that updates Firestore once generation completes.
  Future<void> generateAndSaveFeedbackInBackground(SessionModel session) async {
    try {
      final updatedSession = await generateFeedbackForSession(session);
      await FirebaseFirestore.instance.collection('sessions').doc(session.sessionId).update({
        'aiFeedbackText': updatedSession.aiFeedbackText,
        'feedbackStatus': updatedSession.feedbackStatus,
        'instructorNote': updatedSession.instructorNote,
      });
    } catch (e) {
      await FirebaseFirestore.instance.collection('sessions').doc(session.sessionId).update({
        'feedbackStatus': 'Feedback Generation Failed',
      });
    }
  }
}
