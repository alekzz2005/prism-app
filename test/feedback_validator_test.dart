import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/aspiration_outcome.dart';
import 'package:prism_app/models/session_model.dart';
import 'package:prism_app/services/feedback_evidence.dart';
import 'package:prism_app/services/feedback_validator.dart';
import 'package:prism_app/services/deterministic_feedback_builder.dart';

SessionModel _createDummySession({
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
    sessionId: 'test_session_123',
    userId: 'user_123',
    studentName: 'Test Student',
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
  group('FeedbackValidator', () {
    test('invented number triggers unsupported_number violation', () {
      final session = _createDummySession();
      final evidence = FeedbackEvidence.fromSession(session);

      // Text introduces 42.7 and 73 which are not allowed numbers
      const text =
          'The insertion angle was 89.5 degrees with a score of 5 out of 5.\n\n'
          'During the aspiration phase, no blood return was observed, achieving a score of 5 out of 5.\n\n'
          'The withdrawal was at 88.0 degrees with a delta of 1.5 degrees, scoring 5 out of 5.\n\n'
          'Maintain this alignment with 42.7 millimeters depth and 73 percent steadiness.';

      final violations = FeedbackValidator.validate(text, evidence);
      expect(violations, contains(FeedbackValidator.violationUnsupportedNumber));
    });

    test('no-blood outcome with blood claim triggers aspiration_conflict', () {
      final session = _createDummySession(aspirationResult: 'No Bleeding');
      final evidence = FeedbackEvidence.fromSession(session);

      const text =
          'The needle insertion was performed at 89.5 degrees with a score of 5 out of 5.\n\n'
          'Aspiration revealed vascular puncture with visible blood return, requiring stoppage.\n\n'
          'The withdrawal was at 88.0 degrees with an angular delta of 1.5 degrees.\n\n'
          'Ensure proper needle position to prevent vascular entry on subsequent attempts.';

      final violations = FeedbackValidator.validate(text, evidence);
      expect(violations, contains(FeedbackValidator.violationAspirationConflict));
    });

    test('blood outcome with "safe" triggers aspiration_conflict', () {
      final session = _createDummySession(
        aspirationResult: 'Bleeding Detected',
        aspirationScore: 1,
      );
      final evidence = FeedbackEvidence.fromSession(session);

      const text =
          'The needle insertion was performed at 89.5 degrees with a score of 5 out of 5.\n\n'
          'The aspiration check was safe to inject into muscle with no blood observed.\n\n'
          'The withdrawal was at 88.0 degrees with an angular delta of 1.5 degrees.\n\n'
          'Continue to maintain correct anatomical landmarks during return demonstrations.';

      final violations = FeedbackValidator.validate(text, evidence);
      expect(violations, contains(FeedbackValidator.violationAspirationConflict));
    });

    test('notRecorded with blood claim either way triggers aspiration_conflict', () {
      final session = _createDummySession(aspirationResult: 'Not Detected');
      final evidence = FeedbackEvidence.fromSession(session);
      expect(evidence.aspirationOutcome, equals(AspirationOutcome.notRecorded));

      // 1. Claiming no blood
      const textNoBlood =
          'The needle insertion was performed at 89.5 degrees with a score of 5 out of 5.\n\n'
          'No blood was observed during the procedure, confirming intramuscular placement.\n\n'
          'The withdrawal was at 88.0 degrees with an angular delta of 1.5 degrees.\n\n'
          'Ensure correct technique on all return demonstrations.';

      final violations1 = FeedbackValidator.validate(textNoBlood, evidence);
      expect(violations1, contains(FeedbackValidator.violationAspirationConflict));

      // 2. Claiming bleeding detected
      const textBleeding =
          'The needle insertion was performed at 89.5 degrees with a score of 5 out of 5.\n\n'
          'Bleeding was observed during aspiration indicating vascular entry.\n\n'
          'The withdrawal was at 88.0 degrees with an angular delta of 1.5 degrees.\n\n'
          'Always abort injection when blood is detected.';

      final violations2 = FeedbackValidator.validate(textBleeding, evidence);
      expect(violations2, contains(FeedbackValidator.violationAspirationConflict));
    });

    test('"seconds" or "duration" with null duration triggers unsupported_term', () {
      final session = _createDummySession(aspirationDuration: 0.0);
      final evidence = FeedbackEvidence.fromSession(session);
      expect(evidence.aspirationDuration, isNull);

      const text =
          'The needle insertion was performed at 89.5 degrees with a score of 5 out of 5.\n\n'
          'The aspiration phase lasted for 5 seconds without blood return.\n\n'
          'The withdrawal was at 88.0 degrees with an angular delta of 1.5 degrees.\n\n'
          'Maintain steady alignment during return demonstrations.';

      final violations = FeedbackValidator.validate(text, evidence);
      expect(violations, contains(FeedbackValidator.violationUnsupportedTerm));
    });

    test('unsupported terms (wrist, steadiness, speed, smoothness) trigger violation', () {
      final session = _createDummySession();
      final evidence = FeedbackEvidence.fromSession(session);

      const text =
          'The needle insertion was performed at 89.5 degrees with a score of 5 out of 5.\n\n'
          'During the aspiration phase across 3.5 seconds, no blood return was observed.\n\n'
          'The withdrawal at 88.0 degrees showed excellent wrist smoothness and hand steadiness.\n\n'
          'Maintain this alignment during return demonstrations.';

      final violations = FeedbackValidator.validate(text, evidence);
      expect(violations, contains(FeedbackValidator.violationUnsupportedTerm));
    });

    test('compliant text passes validation without violations', () {
      final session = _createDummySession();
      final evidence = FeedbackEvidence.fromSession(session);

      final compliantText = DeterministicFeedbackBuilder.build(evidence);
      final violations = FeedbackValidator.validate(compliantText, evidence);
      expect(violations, isEmpty);
    });

    test('deterministic builder output always passes the validator across permutations', () {
      final testCases = [
        // Standard noBleeding with duration and drift
        _createDummySession(
          aspirationResult: 'No Bleeding',
          aspirationScore: 5,
          aspirationDuration: 3.5,
          aspirationAngleDrift: 1.2,
        ),
        // Bleeding detected
        _createDummySession(
          aspirationResult: 'Bleeding Detected',
          aspirationScore: 1,
          aspirationDuration: 2.0,
          aspirationAngleDrift: 0.8,
          overallScore: 2,
          flagged: true,
        ),
        // Not recorded with 0 duration and null drift
        _createDummySession(
          aspirationResult: 'Not Detected',
          aspirationScore: 1,
          aspirationDuration: 0.0,
          aspirationAngleDrift: null,
          overallScore: 3,
        ),
        // Low insertion score
        _createDummySession(
          insertionAngle: 75.0,
          insertionScore: 2,
          aspirationResult: 'No Bleeding',
          aspirationScore: 5,
          withdrawalAngle: 74.0,
          withdrawalScore: 5,
          angularDelta: 1.0,
          overallScore: 4,
        ),
        // Low withdrawal score
        _createDummySession(
          insertionAngle: 90.0,
          insertionScore: 5,
          aspirationResult: 'No Bleeding',
          aspirationScore: 5,
          withdrawalAngle: 70.0,
          withdrawalScore: 2,
          angularDelta: 20.0,
          correspondenceResult: 'Deviates',
          overallScore: 4,
        ),
      ];

      for (final session in testCases) {
        final evidence = FeedbackEvidence.fromSession(session);
        final text = DeterministicFeedbackBuilder.build(evidence);
        final violations = FeedbackValidator.validate(text, evidence);
        expect(
          violations,
          isEmpty,
          reason: 'Failed for session with outcome: ${evidence.aspirationOutcome}, '
              'duration: ${evidence.aspirationDuration}, drift: ${evidence.needleDrift}. '
              'Violations: $violations\nText:\n$text',
        );
      }
    });
  });
}
