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
    // Match any numeric token (integer or decimal)
    final numRegex = RegExp(r'(?<![a-zA-Z0-9_])(\d+(?:\.\d+)?)(?![a-zA-Z0-9_])');
    for (final match in numRegex.allMatches(trimmed)) {
      final token = match.group(1);
      if (token == null) continue;
      final val = double.tryParse(token);
      if (val == null) continue;

      final isAllowed = evidence.allowedNumbers.any(
        (allowed) => (val - allowed).abs() <= 0.05,
      );
      if (!isAllowed) {
        violations.add(violationUnsupportedNumber);
        break;
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
}
