import 'package:flutter/foundation.dart';
import '../core/injection_config.dart';

/// Holds all live in-session state during a detection run.
/// Call resetSession() before returning to InjectionTypeScreen.
class SessionStateProvider extends ChangeNotifier {
  InjectionConfig? currentConfig;

  double? insertionAngle;
  int? insertionScore;

  String? aspirationResult;
  double? aspirationDuration;
  String? motionSmoothness;

  double? withdrawalAngle;
  int? withdrawalScore;

  String? correspondenceResult;
  double? angularDelta;

  int? overallScore;
  bool flagged = false;

  void setConfig(InjectionConfig config) {
    currentConfig = config;
    notifyListeners();
  }

  void setInsertion(double angle, int score) {
    insertionAngle = angle;
    insertionScore = score;
    notifyListeners();
  }

  void setAspiration({
    required String result,
    required double duration,
    required String smoothness,
  }) {
    aspirationResult = result;
    aspirationDuration = duration;
    motionSmoothness = smoothness;
    notifyListeners();
  }

  void setWithdrawal(double angle, int score) {
    withdrawalAngle = angle;
    withdrawalScore = score;
    notifyListeners();
  }

  void setCorrespondence(String result, double delta) {
    correspondenceResult = result;
    angularDelta = delta;
    notifyListeners();
  }

  void setOverallScore(int score) {
    overallScore = score;
    notifyListeners();
  }

  void setFlagged(bool value) {
    flagged = value;
    notifyListeners();
  }

  /// Clears all session state. Call before returning to InjectionTypeScreen.
  void resetSession() {
    currentConfig = null;
    insertionAngle = null;
    insertionScore = null;
    aspirationResult = null;
    aspirationDuration = null;
    motionSmoothness = null;
    withdrawalAngle = null;
    withdrawalScore = null;
    correspondenceResult = null;
    angularDelta = null;
    overallScore = null;
    flagged = false;
    notifyListeners();
  }
}
