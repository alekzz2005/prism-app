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

  group('label', () {
    test('returns user-friendly labels', () {
      expect(AspirationOutcome.noBleeding.label, equals('No blood'));
      expect(AspirationOutcome.bleedingDetected.label, equals('Blood present'));
      expect(AspirationOutcome.notRecorded.label, equals('Not recorded'));
    });
  });
}
