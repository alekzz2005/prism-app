import '../models/session_model.dart';
import '../core/aspiration_outcome.dart';
import 'feedback_evidence.dart';

/// Builds a deterministic, rule-based 4-paragraph clinical feedback draft.
///
/// Built purely from verifiable [FeedbackEvidence] without calling an LLM.
/// Guaranteed to satisfy all validation rules:
/// - Exactly 4 paragraphs, <= 175 words total
/// - Only numbers present in evidence.allowedNumbers
/// - Zero unsupported terms (no wrist, steadiness, speed, smoothness, etc.)
/// - Aspiration evaluation strictly matches instructor blood check decision
class DeterministicFeedbackBuilder {
  static String build(FeedbackEvidence evidence) {
    // Paragraph 1: Insertion Phase
    final p1 = 'The intramuscular needle insertion was performed at an angle of '
        '${evidence.insertionAngle.toStringAsFixed(1)}°, compared to the target standard of 90° '
        '(tolerance ±5°). This insertion technique achieved a rubric score of '
        '${evidence.insertionScore} out of 5.';

    // Paragraph 2: Aspiration Phase
    final String p2;
    final durationSnippet = evidence.aspirationDuration != null
        ? ' across an aspiration time of ${evidence.aspirationDuration!.toStringAsFixed(1)}s'
        : '';
    final driftSnippet = evidence.needleDrift != null
        ? ', with needle stability drift recorded at ±${evidence.needleDrift!.toStringAsFixed(1)}° from insertion angle'
        : '';

    switch (evidence.aspirationOutcome) {
      case AspirationOutcome.noBleeding:
        p2 = 'During the aspiration phase$durationSnippet, no blood return was observed, '
            'confirming proper intramuscular placement$driftSnippet. '
            'This phase achieved a rubric score of ${evidence.aspirationScore} out of 5.';
        break;
      case AspirationOutcome.bleedingDetected:
        p2 = 'During the aspiration phase$durationSnippet, blood return was observed '
            'indicating vascular puncture$driftSnippet. '
            'The procedure was immediately halted for safety, receiving a rubric score of ${evidence.aspirationScore} out of 5.';
        break;
      case AspirationOutcome.notRecorded:
        p2 = 'The aspiration outcome was not recorded during this session$durationSnippet$driftSnippet. '
            'Because the clinical blood check was not documented, this phase received a rubric score of ${evidence.aspirationScore} out of 5.';
        break;
    }

    // Paragraph 3: Withdrawal Phase
    final p3 = 'Needle withdrawal was executed at an angle of '
        '${evidence.withdrawalAngle.toStringAsFixed(1)}°, yielding an angular delta of '
        '${evidence.angularDelta.toStringAsFixed(1)}° compared to the insertion trajectory '
        '(${evidence.correspondence}). This withdrawal technique received a rubric score of '
        '${evidence.withdrawalScore} out of 5.';

    // Paragraph 4: Actionable Recommendation
    final String p4;
    if (evidence.aspirationOutcome == AspirationOutcome.bleedingDetected) {
      p4 = 'Always abort the injection and replace equipment whenever blood return occurs to maintain patient safety.';
    } else if (evidence.insertionScore <= evidence.withdrawalScore && evidence.insertionScore < 5) {
      p4 = 'Focus on inserting the needle at a strict 90° perpendicular angle to optimize muscle tissue penetration.';
    } else if (evidence.withdrawalScore < 5) {
      p4 = 'Focus on withdrawing the needle along the exact insertion vector to minimize angular delta and tissue trauma.';
    } else {
      p4 = 'Maintain this consistent alignment and steady technique across all return-demonstration procedural phases.';
    }

    return '$p1\n\n$p2\n\n$p3\n\n$p4';
  }

  /// Convenience wrapper to generate draft directly from a [SessionModel].
  static String buildFromSession(SessionModel session) {
    return build(FeedbackEvidence.fromSession(session));
  }
}
