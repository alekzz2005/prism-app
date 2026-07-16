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
      'IM' => 'CIT-U rubric: dart-like motion at 90 deg, inject slowly (~10 sec/ml), wait 10s, smoothly withdraw at same angle of insertion.',
      _ => '',
    };

    return '$clinicalContext\n'
        '${session.injectionType} injection RD results:\n'
        'Target angle: ${config.targetAngle.toStringAsFixed(0)} deg (tolerance ±${config.tolerance.toStringAsFixed(0)} deg)\n'
        'Insertion: ${session.insertionAngle.toStringAsFixed(1)} deg, rubric ${session.insertionScore}/5\n'
        'Withdrawal: ${session.withdrawalAngle.toStringAsFixed(1)} deg, rubric ${session.withdrawalScore}/5\n'
        'Angular delta (insertion vs withdrawal): ${session.angularDelta.toStringAsFixed(1)} deg, ${session.correspondenceResult}\n'
        'Overall rubric: ${session.overallScore}/5'
        '${session.flagged ? '\nFLAGGED: one or more components were undetectable' : ''}';
  }
}

/// Orchestrates AI feedback generation and Firestore session persistence.
class FeedbackService {
  final _client = OpenRouterApiClient();

  /// Builds prompt, calls OpenRouter, and returns a new SessionModel with the AI feedback populated.
  Future<SessionModel> generateFeedbackForSession(SessionModel session) async {
    final prompt = PayloadBuilder.buildPrompt(session);
    String feedbackText = '';
    String feedbackStatus = 'Pending';

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
