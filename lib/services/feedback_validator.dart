import 'feedback_evidence.dart';
import '../core/aspiration_outcome.dart';

/// Validates generated clinical AI feedback against ground-truth evidence facts.
///
/// Returns violation codes:
/// - 'unsupported_number': A numeric token not within ±0.05 of any allowed number.
/// - 'aspiration_conflict': Contradicts instructor blood check decision.
/// - 'unsupported_term': Mentions unmeasured physical traits or unrecorded duration.
/// - 'structure': Not exactly 4 paragraphs or exceeds 175 words total.
class FeedbackValidator {
  static const String violationUnsupportedNumber = 'unsupported_number';
  static const String violationAspirationConflict = 'aspiration_conflict';
  static const String violationUnsupportedTerm = 'unsupported_term';
  static const String violationStructure = 'structure';

  /// Validates [text] against ground-truth [evidence].
  /// Returns a list of distinct violation codes. Empty list means passed.
  static List<String> validate(String text, FeedbackEvidence evidence) {
    final violations = <String>{};
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return [violationStructure];
    }

    // ── 1. Numeric Token Validation ──────────────────────────────────────────
    // Rubric step numbers (19, 20, 21) are accepted ONLY when explicitly qualified as "step N" or "steps N"
    final stepRegex = RegExp(
      r'\b(?:step|steps)\s*(?:19|20|21)(?:\s*(?:[-–]|to)\s*(?:19|20|21))*\b',
      caseSensitive: false,
    );
    final textForNumCheck = trimmed
        .replaceAll(stepRegex, ' ')
        .replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)[sS]\b'), (m) => '${m.group(1)} ');

    final numRegex = RegExp(r'(?<![a-zA-Z0-9_])(\d+(?:\.\d+)?)(?![a-zA-Z0-9_])');
    for (final match in numRegex.allMatches(textForNumCheck)) {
      final token = match.group(1);
      if (token == null) continue;
      final val = double.tryParse(token);
      if (val == null) continue;

      final isAllowed = evidence.allowedNumbers.any(
        (allowed) => (val - allowed).abs() <= 0.15,
      );
      if (!isAllowed) {
        violations.add('$violationUnsupportedNumber:$token');
      }
    }

    // ── 2. Aspiration Conflict Validation ────────────────────────────────────
    switch (evidence.aspirationOutcome) {
      case AspirationOutcome.noBleeding:
        // Text must not assert blood, bleeding, or vascular puncture
        final sanitized = trimmed.replaceAll(
          RegExp(r'\b(no blood(?: return)?|no bleeding|without blood(?: return)?|absence of blood|negative for blood|free of blood)\b', caseSensitive: false),
          '',
        );
        if (RegExp(r'\b(blood(?: return)?|bleeding|vascular puncture)\b', caseSensitive: false).hasMatch(sanitized)) {
          violations.add(violationAspirationConflict);
        }
        break;

      case AspirationOutcome.bleedingDetected:
        // Text must not claim no blood, safe injection, or correct aspiration
        if (RegExp(r'\b(safe|no blood(?: return)?|correct aspiration|safe to inject)\b', caseSensitive: false).hasMatch(trimmed)) {
          violations.add(violationAspirationConflict);
        }
        break;

      case AspirationOutcome.notRecorded:
        // Text must not comment on blood presence either way
        if (RegExp(r'\b(blood(?: return)?|bleeding|vascular puncture)\b', caseSensitive: false).hasMatch(trimmed)) {
          violations.add(violationAspirationConflict);
        }
        break;
    }

    // ── 3. Unsupported Term Validation ───────────────────────────────────────
    final unsupportedTermPatterns = <String>[
      r'\bwrist\b',
      r'\bsteadiness\b',
      r'\bhand steadiness\b',
      r'\bspeed\b',
      r'\bsmoothness\b',
      r'\bneuromuscular\b',
      r'camera[- ]detected blood',
      r'detected by (?:the )?camera',
      r'camera detection',
      r'proper placement',
      r'confirming placement',
      r'proper intramuscular placement',
      r'confirming proper',
    ];

    if (evidence.aspirationDuration == null) {
      unsupportedTermPatterns.add(r'\bseconds?\b');
      unsupportedTermPatterns.add(r'\bduration\b');
    }

    for (final pattern in unsupportedTermPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(trimmed)) {
        violations.add(violationUnsupportedTerm);
        break;
      }
    }

    // ── 4. Structure Validation ──────────────────────────────────────────────
    final paragraphs = trimmed
        .split(RegExp(r'\n\s*\n+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    final words = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (paragraphs.length != 4 || words.length > 175) {
      violations.add(violationStructure);
    }

    return violations.toList();
  }

  /// Generates specific, human-readable correction instructions for any violations found in [text].
  /// Used in the regeneration prompt so the model is informed of the exact offending values.
  static List<String> getCorrectionInstructions(String text, FeedbackEvidence evidence) {
    final instructions = <String>[];
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return ['The draft was empty: provide exactly 4 paragraphs adhering to the clinical format.'];
    }

    // 1. Numeric violations
    final stepRegex = RegExp(
      r'\b(?:step|steps)\s*(?:19|20|21)(?:\s*(?:[-–]|to)\s*(?:19|20|21))*\b',
      caseSensitive: false,
    );
    final textForNumCheck = trimmed
        .replaceAll(stepRegex, ' ')
        .replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)[sS]\b'), (m) => '${m.group(1)} ');

    final numRegex = RegExp(r'(?<![a-zA-Z0-9_])(\d+(?:\.\d+)?)(?![a-zA-Z0-9_])');
    final offendingNumbers = <String>{};
    for (final match in numRegex.allMatches(textForNumCheck)) {
      final token = match.group(1);
      if (token == null) continue;
      final val = double.tryParse(token);
      if (val == null) continue;

      final isAllowed = evidence.allowedNumbers.any(
        (allowed) => (val - allowed).abs() <= 0.15,
      );
      if (!isAllowed) {
        offendingNumbers.add(token);
      }
    }
    if (offendingNumbers.isNotEmpty) {
      final plural = offendingNumbers.length > 1;
      instructions.add(
        'The number${plural ? 's' : ''} ${offendingNumbers.join(', ')} ${plural ? 'are' : 'is'} not in the recorded metrics: remove ${plural ? 'them' : 'it'} or use ONLY numbers from the payload.',
      );
    }

    // 2. Aspiration conflicts
    switch (evidence.aspirationOutcome) {
      case AspirationOutcome.noBleeding:
        final sanitized = trimmed.replaceAll(
          RegExp(r'\b(no blood(?: return)?|no bleeding|without blood(?: return)?|absence of blood|negative for blood|free of blood)\b', caseSensitive: false),
          '',
        );
        if (RegExp(r'\b(blood(?: return)?|bleeding|vascular puncture)\b', caseSensitive: false).hasMatch(sanitized)) {
          instructions.add(
            'The aspiration check confirmed no blood return (safe intramuscular placement): do not state blood return was observed, and do not mention vascular puncture.',
          );
        }
        break;

      case AspirationOutcome.bleedingDetected:
        if (RegExp(r'\b(safe|no blood(?: return)?|correct aspiration|safe to inject)\b', caseSensitive: false).hasMatch(trimmed)) {
          instructions.add(
            'The aspiration check confirmed vascular puncture (blood return detected): do not claim injection was safe or that no blood was observed.',
          );
        }
        break;

      case AspirationOutcome.notRecorded:
        if (RegExp(r'\b(blood(?: return)?|bleeding|vascular puncture)\b', caseSensitive: false).hasMatch(trimmed)) {
          instructions.add(
            'Aspiration blood check was not recorded: do not comment on blood presence or absence.',
          );
        }
        break;
    }

    // 3. Unsupported terms
    final unsupportedTermPatterns = <String, String>{
      r'\bwrist\b': 'wrist',
      r'\bsteadiness\b': 'steadiness',
      r'\bhand steadiness\b': 'hand steadiness',
      r'\bspeed\b': 'speed',
      r'\bsmoothness\b': 'smoothness',
      r'\bneuromuscular\b': 'neuromuscular',
      r'camera[- ]detected blood': 'camera-detected blood',
      r'detected by (?:the )?camera': 'detected by camera',
      r'camera detection': 'camera detection',
      r'proper placement': 'proper placement',
      r'confirming placement': 'confirming placement',
      r'proper intramuscular placement': 'proper placement',
      r'confirming proper': 'confirming placement',
    };

    if (evidence.aspirationDuration == null) {
      unsupportedTermPatterns[r'\bseconds?\b'] = 'seconds';
      unsupportedTermPatterns[r'\bduration\b'] = 'duration';
    }

    final matchedTerms = <String>{};
    for (final entry in unsupportedTermPatterns.entries) {
      if (RegExp(entry.key, caseSensitive: false).hasMatch(trimmed)) {
        matchedTerms.add(entry.value);
      }
    }
    if (matchedTerms.isNotEmpty) {
      instructions.add(
        'Remove unmeasured claims (${matchedTerms.join(', ')}): PRISM does not measure physical stability/speed/smoothness or detect blood via camera.',
      );
    }

    // 4. Structure
    final paragraphs = trimmed
        .split(RegExp(r'\n\s*\n+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    final words = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (paragraphs.length != 4) {
      instructions.add('The previous draft had ${paragraphs.length} paragraphs: rewrite to have exactly 4 paragraphs.');
    }
    if (words.length > 175) {
      instructions.add('The previous draft had ${words.length} words: condense to no more than 175 words total.');
    }

    return instructions;
  }
}
