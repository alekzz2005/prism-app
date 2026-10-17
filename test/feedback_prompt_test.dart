import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/aspiration_outcome.dart';
import 'package:prism_app/models/session_model.dart';
import 'package:prism_app/services/feedback_evidence.dart';
import 'package:prism_app/services/feedback_service.dart';

SessionModel _createTestSession({
  double insertionAngle = 89.5,
  int insertionScore = 5,
  String aspirationResult = 'No Bleeding',
  int aspirationScore = 5,
  double? aspirationAngleDrift = 1.2,
  double aspirationDuration = 3.5,
  double withdrawalAngle = 88.0,
  int withdrawalScore = 5,
  double angularDelta = 1.5,
  String correspondenceResult = 'Matches',
  int overallScore = 5,
  bool flagged = false,
}) {
  return SessionModel(
    sessionId: 'test_session_prompt',
    userId: 'user_prompt',
    studentName: 'Prompt Test Student',
    timestamp: Timestamp.now(),
    injectionType: 'IM',
    insertionAngle: insertionAngle,
    insertionScore: insertionScore,
    aspirationResult: aspirationResult,
    aspirationScore: aspirationScore,
    aspirationAngleDrift: aspirationAngleDrift,
    aspirationDuration: aspirationDuration,
    motionSmoothness: 'Good',
    withdrawalAngle: withdrawalAngle,
    withdrawalScore: withdrawalScore,
    angularDelta: angularDelta,
    correspondenceResult: correspondenceResult,
    overallScore: overallScore,
    aiFeedbackText: '',
    feedbackStatus: 'Pending',
    instructorNote: '',
    flagged: flagged,
  );
}

void main() {
  group('PayloadBuilder Prompt Generation', () {
    test('prompt omits duration and drift when not recorded', () {
      final session = _createTestSession(
        aspirationDuration: 0.0,
        aspirationAngleDrift: null,
      );
      final prompt = PayloadBuilder.buildPrompt(session);

      expect(prompt, contains('• Duration: not recorded'));
      expect(prompt, contains('• Needle Stability Drift: not recorded'));
      expect(prompt, isNot(contains('5-10s')));
    });

    test('prompt includes duration and drift when recorded', () {
      final session = _createTestSession(
        aspirationDuration: 4.2,
        aspirationAngleDrift: 1.5,
      );
      final prompt = PayloadBuilder.buildPrompt(session);

      expect(prompt, contains('• Duration: 4.2s'));
      expect(prompt, contains('• Needle Stability Drift: ±1.5° from insertion angle'));
      expect(prompt, isNot(contains('5-10s')));
    });

    test('prompt aspiration check for notRecorded gives neutral instruction', () {
      final session = _createTestSession(aspirationResult: 'Not Detected');
      final prompt = PayloadBuilder.buildPrompt(session);

      expect(
        prompt,
        contains('• Aspiration Blood Check: Aspiration outcome not recorded; do not comment on blood presence'),
      );
      expect(prompt, isNot(contains('5-10s')));
    });

    test('prompt aspiration check for bleedingDetected describes vascular puncture', () {
      final session = _createTestSession(
        aspirationResult: 'Bleeding Detected',
        aspirationScore: 1,
        flagged: true,
      );
      final prompt = PayloadBuilder.buildPrompt(session);

      expect(
        prompt,
        contains('• Aspiration Blood Check: Bleeding Detected (Blood return detected — vascular puncture, clinical risk)'),
      );
      expect(prompt, contains('FLAGGED'));
    });

    test('prompt aspiration check for noBleeding describes safe muscle tissue', () {
      final session = _createTestSession(
        aspirationResult: 'No Bleeding',
        aspirationScore: 5,
      );
      final prompt = PayloadBuilder.buildPrompt(session);

      expect(
        prompt,
        contains('• Aspiration Blood Check: No Bleeding (No blood return — correct technique, muscle tissue safe)'),
      );
    });

    test('buildPromptFromEvidence produces identical output', () {
      final session = _createTestSession();
      final evidence = FeedbackEvidence.fromSession(session);

      final promptFromSession = PayloadBuilder.buildPrompt(session);
      final promptFromEvidence = PayloadBuilder.buildPromptFromEvidence(evidence);

      expect(promptFromEvidence, equals(promptFromSession));
    });
  });
}
