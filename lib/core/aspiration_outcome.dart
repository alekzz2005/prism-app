import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/session_model.dart';

/// Aspiration outcome single source of truth for PRISM.
///
/// Implements CIT-U rubric and validation finding decisions:
/// The camera cannot detect blood return. The instructor observes the aspiration
/// and presses Stop (blood present) or Continue (no blood).
/// Aspiration is scored purely from this decision:
/// - No blood (Continue) -> 5
/// - Blood present (Stop) -> 1, flagged
/// - Not recorded -> 1, flagged
enum AspirationOutcome {
  noBleeding,
  bleedingDetected,
  notRecorded;

  /// Parses raw aspiration strings from Firestore or UI into a canonical outcome.
  ///
  /// Maps legacy strings:
  /// - 'No Bleeding', 'No', 'Correct' -> [noBleeding]
  /// - 'Bleeding Detected', 'Failed (Bleeding)' -> [bleedingDetected]
  /// - All other values (including 'Not Detected', null, empty string) -> [notRecorded]
  static AspirationOutcome parse(String? raw) {
    if (raw == null) return AspirationOutcome.notRecorded;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return AspirationOutcome.notRecorded;

    switch (trimmed) {
      case 'No Bleeding':
      case 'No':
      case 'Correct':
        return AspirationOutcome.noBleeding;
      case 'Bleeding Detected':
      case 'Failed (Bleeding)':
        return AspirationOutcome.bleedingDetected;
      default:
        return AspirationOutcome.notRecorded;
    }
  }

  /// Whether this outcome requires the session to be flagged for review / safety.
  /// True for [bleedingDetected] and [notRecorded].
  bool get needsFlag {
    switch (this) {
      case AspirationOutcome.noBleeding:
        return false;
      case AspirationOutcome.bleedingDetected:
      case AspirationOutcome.notRecorded:
        return true;
    }
  }

  /// Human-readable label for UI display and reporting:
  /// 'No blood' / 'Blood present' / 'Not recorded'
  String get label {
    switch (this) {
      case AspirationOutcome.noBleeding:
        return 'No blood';
      case AspirationOutcome.bleedingDetected:
        return 'Blood present';
      case AspirationOutcome.notRecorded:
        return 'Not recorded';
    }
  }

  /// Convenience getter matching [aspirationScore].
  int get score => aspirationScore(this);
}

/// Pure function returning the CIT-U 1-5 rubric score for an aspiration outcome:
/// - 5 for [AspirationOutcome.noBleeding]
/// - 1 otherwise ([AspirationOutcome.bleedingDetected] or [AspirationOutcome.notRecorded])
int aspirationScore(AspirationOutcome o) {
  switch (o) {
    case AspirationOutcome.noBleeding:
      return 5;
    case AspirationOutcome.bleedingDetected:
    case AspirationOutcome.notRecorded:
      return 1;
  }
}

/// Standard guard text used when an injection session is aborted due to blood return during aspiration.
const String bloodSessionGuardText =
    'Session automatically flagged: Blood return was observed during aspiration. In clinical practice, the injection must be aborted immediately without injecting medication, the needle safely withdrawn, and the procedure restarted with new equipment.';

/// Pure helper returning whether needle withdrawal was performed for a given session.
/// Returns false when blood return was observed (the session is stopped after aspiration).
bool isWithdrawalPerformed(bool? bleedingObserved) => bleedingObserved != true;

/// Builds a stopped session document when blood return is observed during aspiration.
/// Withdrawal is not performed, not scored, and the session is automatically flagged with overallScore 1.
SessionModel createBleedingStoppedSession({
  required String userId,
  required String studentName,
  required String injectionType,
  String? sectionName,
  String? partnerName,
  required double insertionAngle,
  required int insertionScore,
  required double? aspirationAngleDrift,
  required double aspirationDuration,
  String? insertionImageBase64,
  String? aspirationImageBase64,
  bool isPractice = false,
  String instructorNote = '',
  String sessionId = '',
}) {
  return SessionModel(
    sessionId: sessionId,
    userId: userId,
    studentName: studentName,
    timestamp: Timestamp.now(),
    injectionType: injectionType,
    sectionName: sectionName ?? '',
    partnerName: partnerName ?? '',
    insertionAngle: insertionAngle,
    insertionScore: insertionScore,
    aspirationResult: 'Bleeding Detected',
    aspirationScore: 1,
    bleedingObserved: true,
    aspirationAngleDrift: aspirationAngleDrift,
    aspirationDuration: aspirationDuration,
    motionSmoothness: 'N/A',
    withdrawalAngle: 0.0,
    withdrawalScore: 1,
    correspondenceResult: 'Deviates',
    angularDelta: 0.0,
    overallScore: 1, // Automatic fail on blood return
    aiFeedbackText: bloodSessionGuardText,
    aiFeedbackOriginal: bloodSessionGuardText,
    feedbackStatus: isPractice ? 'Released' : 'Pending',
    releaseTimestamp: isPractice ? Timestamp.now() : null,
    instructorNote: isPractice
        ? instructorNote
        : (instructorNote.isNotEmpty
            ? instructorNote
            : 'Instructor cancelled session: Patient bleeding detected during aspiration.'),
    flagged: true,
    insertionImageBase64: insertionImageBase64,
    aspirationImageBase64: aspirationImageBase64,
    withdrawalImageBase64: null,
    isPractice: isPractice,
  );
}
