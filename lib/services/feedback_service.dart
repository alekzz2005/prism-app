import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/session_model.dart';
import '../core/aspiration_outcome.dart';
import 'feedback_evidence.dart';
import 'openrouter_api_client.dart';
import 'feedback_exceptions.dart';

/// Builds a compact, structured LLM prompt from the finalized SessionModel.
/// Uses key:value pairs to minimise input tokens while maximising context.
class PayloadBuilder {
  static String buildPrompt(SessionModel session) {
    final evidence = FeedbackEvidence.fromSession(session);
    return buildPromptFromEvidence(evidence);
  }

  static String buildPromptFromEvidence(FeedbackEvidence evidence) {
    const clinicalContext =
        'CIT-U Rubric: Intramuscular (IM) Injection Return-Demonstration (Chronological Procedural Evaluation)';

    final String aspirationCheck = switch (evidence.aspirationOutcome) {
      AspirationOutcome.notRecorded =>
        'Aspiration outcome not recorded; do not comment on blood presence',
      AspirationOutcome.bleedingDetected =>
        'Bleeding Detected (Blood return detected — vascular puncture, clinical risk)',
      AspirationOutcome.noBleeding =>
        'No Bleeding (No blood return — correct technique, muscle tissue safe)',
    };

    final durationText = evidence.aspirationDuration != null
        ? '${evidence.aspirationDuration!.toStringAsFixed(1)}s'
        : 'not recorded';

    final driftText = evidence.needleDrift != null
        ? '±${evidence.needleDrift!.toStringAsFixed(1)}° from insertion angle'
        : 'not recorded';

    return '$clinicalContext\n'
        'Standard: 90° insertion (±${evidence.tolerance.toStringAsFixed(0)}° tolerance), aspirate to check for blood, withdrawal along same vector.\n\n'
        'Step 1 - Insertion Phase:\n'
        '• Target Angle: ${evidence.targetAngle.toStringAsFixed(0)}° (Tolerance ±${evidence.tolerance.toStringAsFixed(0)}°)\n'
        '• Measured Angle: ${evidence.insertionAngle.toStringAsFixed(1)}° (Score: ${evidence.insertionScore}/5)\n\n'
        'Step 2 - Aspiration Phase:\n'
        '• Aspiration Blood Check: $aspirationCheck\n'
        '• Score: ${evidence.aspirationScore}/5\n'
        '• Duration: $durationText\n'
        '• Needle Stability Drift: $driftText\n\n'
        'Step 3 - Withdrawal Phase:\n'
        '• Measured Angle: ${evidence.withdrawalAngle.toStringAsFixed(1)}° (Score: ${evidence.withdrawalScore}/5)\n'
        '• Angular Delta: ${evidence.angularDelta.toStringAsFixed(1)}° (${evidence.correspondence})\n\n'
        'Overall Rubric Score: ${evidence.overallScore}/5'
        '${evidence.flagged ? '\nFLAGGED: One or more components were undetectable or bleeding was detected.' : ''}';
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

    return session.copyWith(
      aiFeedbackText: feedbackText,
      feedbackStatus: feedbackStatus,
      instructorNote: instructorNote,
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
