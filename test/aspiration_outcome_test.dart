import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/core/aspiration_outcome.dart';

void main() {
  group('AspirationOutcome.parse', () {
    test('maps legacy strings for noBleeding correctly', () {
      expect(AspirationOutcome.parse('No Bleeding'), equals(AspirationOutcome.noBleeding));
      expect(AspirationOutcome.parse('No'), equals(AspirationOutcome.noBleeding));
      expect(AspirationOutcome.parse('Correct'), equals(AspirationOutcome.noBleeding));
      expect(AspirationOutcome.parse('  No Bleeding  '), equals(AspirationOutcome.noBleeding));
      expect(AspirationOutcome.parse('  No  '), equals(AspirationOutcome.noBleeding));
      expect(AspirationOutcome.parse('  Correct  '), equals(AspirationOutcome.noBleeding));
    });

    test('maps legacy strings for bleedingDetected correctly', () {
      expect(AspirationOutcome.parse('Bleeding Detected'), equals(AspirationOutcome.bleedingDetected));
      expect(AspirationOutcome.parse('Failed (Bleeding)'), equals(AspirationOutcome.bleedingDetected));
      expect(AspirationOutcome.parse('  Bleeding Detected  '), equals(AspirationOutcome.bleedingDetected));
      expect(AspirationOutcome.parse('  Failed (Bleeding)  '), equals(AspirationOutcome.bleedingDetected));
    });

    test('maps notRecorded, unknown, empty, or null strings to notRecorded', () {
      expect(AspirationOutcome.parse(null), equals(AspirationOutcome.notRecorded));
      expect(AspirationOutcome.parse(''), equals(AspirationOutcome.notRecorded));
      expect(AspirationOutcome.parse('   '), equals(AspirationOutcome.notRecorded));
      expect(AspirationOutcome.parse('Not Detected'), equals(AspirationOutcome.notRecorded));
      expect(AspirationOutcome.parse('unknown'), equals(AspirationOutcome.notRecorded));
      expect(AspirationOutcome.parse('Random String'), equals(AspirationOutcome.notRecorded));
    });
  });

  group('Aspiration Scoring Rule', () {
    test('scores noBleeding as 5', () {
      expect(aspirationScore(AspirationOutcome.noBleeding), equals(5));
      expect(AspirationOutcome.noBleeding.score, equals(5));
    });

    test('scores bleedingDetected as 1', () {
      expect(aspirationScore(AspirationOutcome.bleedingDetected), equals(1));
      expect(AspirationOutcome.bleedingDetected.score, equals(1));
    });

    test('scores notRecorded as 1', () {
      expect(aspirationScore(AspirationOutcome.notRecorded), equals(1));
      expect(AspirationOutcome.notRecorded.score, equals(1));
    });
  });

  group('needsFlag', () {
    test('noBleeding does not need flag', () {
      expect(AspirationOutcome.noBleeding.needsFlag, isFalse);
    });

    test('bleedingDetected needs flag', () {
      expect(AspirationOutcome.bleedingDetected.needsFlag, isTrue);
    });

    test('notRecorded needs flag', () {
      expect(AspirationOutcome.notRecorded.needsFlag, isTrue);
    });
  });

  group('isWithdrawalPerformed', () {
    test('returns false when bleedingObserved is true', () {
      expect(isWithdrawalPerformed(true), isFalse);
    });

    test('returns true when bleedingObserved is false or null', () {
      expect(isWithdrawalPerformed(false), isTrue);
      expect(isWithdrawalPerformed(null), isTrue);
    });
  });

  group('createBleedingStoppedSession', () {
    test('uses bloodSessionGuardText and stops session with overallScore 1', () {
      final session = createBleedingStoppedSession(
        userId: 'student@cit.edu',
        studentName: 'Juan Dela Cruz',
        injectionType: 'IM',
        sectionName: 'BSN-3A',
        partnerName: 'Maria Santos',
        insertionAngle: 88.5,
        insertionScore: 5,
        aspirationAngleDrift: 1.4,
        aspirationDuration: 5.2,
      );

      expect(session.bleedingObserved, isTrue);
      expect(session.aspirationResult, equals('Bleeding Detected'));
      expect(session.overallScore, equals(1));
      expect(session.aiFeedbackText, equals(bloodSessionGuardText));
      expect(session.aiFeedbackOriginal, equals(bloodSessionGuardText));
      expect(session.aiValidationStatus, isNull);
      expect(session.withdrawalAngle, equals(0.0));
      expect(session.withdrawalScore, equals(1));
      expect(session.flagged, isTrue);
      expect(isWithdrawalPerformed(session.bleedingObserved), isFalse);
    });

    test('applies same guard text and overallScore for practice sessions', () {
      final practiceSession = createBleedingStoppedSession(
        userId: 'student@cit.edu',
        studentName: 'Juan Dela Cruz',
        injectionType: 'IM',
        insertionAngle: 90.0,
        insertionScore: 5,
        aspirationAngleDrift: 0.5,
        aspirationDuration: 4.0,
        isPractice: true,
      );

      expect(practiceSession.isPractice, isTrue);
      expect(practiceSession.bleedingObserved, isTrue);
      expect(practiceSession.overallScore, equals(1));
      expect(practiceSession.aiFeedbackText, equals(bloodSessionGuardText));
      expect(practiceSession.aiFeedbackOriginal, equals(bloodSessionGuardText));
      expect(practiceSession.aiValidationStatus, isNull);
      expect(practiceSession.feedbackStatus, equals('Released'));
    });
  });
}

