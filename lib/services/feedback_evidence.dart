import '../models/session_model.dart';
import '../core/aspiration_outcome.dart';
import '../core/injection_config.dart';

/// Pure-Dart evidence facts model extracted from a SessionModel.
///
/// Holds ONLY measured or instructor-decided clinical telemetry.
/// Ensures all AI prompt statements and post-generation validations
/// are strictly grounded in verifiable session metrics.
class FeedbackEvidence {
  final double targetAngle;
  final double tolerance;
  final double insertionAngle;
  final int insertionScore;
  final AspirationOutcome aspirationOutcome;
  final int aspirationScore;
  final double? needleDrift;
  final double? aspirationDuration;
  final double withdrawalAngle;
  final int withdrawalScore;
  final double angularDelta;
  final String correspondence;
  final int overallScore;
  final bool flagged;
  final Set<double> allowedNumbers;

  const FeedbackEvidence({
    required this.targetAngle,
    required this.tolerance,
    required this.insertionAngle,
    required this.insertionScore,
    required this.aspirationOutcome,
    required this.aspirationScore,
    this.needleDrift,
    this.aspirationDuration,
    required this.withdrawalAngle,
    required this.withdrawalScore,
    required this.angularDelta,
    required this.correspondence,
    required this.overallScore,
    required this.flagged,
    required this.allowedNumbers,
  });

  /// Extracts structured evidence facts from [session].
  factory FeedbackEvidence.fromSession(SessionModel session) {
    InjectionConfig? config;
    try {
      config = InjectionConfigService.getConfig(session.injectionType);
    } catch (_) {
      config = const InjectionConfig(type: 'IM', targetAngle: 90.0, tolerance: 5.0);
    }

    final target = config.targetAngle;
    final tol = config.tolerance;
    final insAngle = session.insertionAngle;
    final insScore = session.insertionScore;
    final aspOutcome = AspirationOutcome.parse(session.aspirationResult);
    final aspScore = session.aspirationScore;
    final drift = session.aspirationAngleDrift;
    final aspDuration = (session.aspirationDuration > 0) ? session.aspirationDuration : null;
    final wthAngle = session.withdrawalAngle;
    final wthScore = session.withdrawalScore;
    final delta = session.angularDelta;
    final correspondence = session.correspondenceResult;
    final ovrScore = session.overallScore;
    final isFlagged = session.flagged || aspOutcome.needsFlag;

    // Allowed numeric values that may legally appear in prompt/feedback text
    final insDeviation = (target - insAngle).abs();
    final wthDeviation = (target - wthAngle).abs();
    final allowed = <double>{
      0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 90.0,
      target,
      tol,
      target - tol,
      target + tol,
      insAngle,
      double.parse(insAngle.toStringAsFixed(1)),
      insAngle.roundToDouble(),
      insAngle.floorToDouble(),
      insDeviation,
      double.parse(insDeviation.toStringAsFixed(1)),
      insDeviation.roundToDouble(),
      insDeviation.floorToDouble(),
      insScore.toDouble(),
      aspScore.toDouble(),
      wthAngle,
      double.parse(wthAngle.toStringAsFixed(1)),
      wthAngle.roundToDouble(),
      wthAngle.floorToDouble(),
      wthDeviation,
      double.parse(wthDeviation.toStringAsFixed(1)),
      wthDeviation.roundToDouble(),
      wthDeviation.floorToDouble(),
      wthScore.toDouble(),
      delta,
      double.parse(delta.toStringAsFixed(1)),
      delta.roundToDouble(),
      delta.floorToDouble(),
      ovrScore.toDouble(),
    };

    if (drift != null) {
      allowed.add(drift);
      allowed.add(double.parse(drift.toStringAsFixed(1)));
      allowed.add(drift.roundToDouble());
      allowed.add(drift.floorToDouble());
    }
    if (aspDuration != null) {
      allowed.add(aspDuration);
      allowed.add(double.parse(aspDuration.toStringAsFixed(1)));
      allowed.add(aspDuration.roundToDouble());
      allowed.add(aspDuration.floorToDouble());
    }

    return FeedbackEvidence(
      targetAngle: target,
      tolerance: tol,
      insertionAngle: insAngle,
      insertionScore: insScore,
      aspirationOutcome: aspOutcome,
      aspirationScore: aspScore,
      needleDrift: drift,
      aspirationDuration: aspDuration,
      withdrawalAngle: wthAngle,
      withdrawalScore: wthScore,
      angularDelta: delta,
      correspondence: correspondence,
      overallScore: ovrScore,
      flagged: isFlagged,
      allowedNumbers: allowed,
    );
  }
}
