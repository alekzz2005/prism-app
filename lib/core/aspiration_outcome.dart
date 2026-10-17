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
