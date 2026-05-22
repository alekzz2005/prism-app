import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents the real-time state of a live return-demonstration session
/// synchronised between the Camera node and the Remote Control node.
class LiveSessionModel {
  final String studentName;
  final String studentEmail;
  final String injectionType;
  final double targetAngle;
  final String phase; // "waiting", "insertion", "aspiration", "withdrawal", "completed"
  final double liveAngle;

  // Stored results to be pushed to final session
  final double? finalInsertionAngle;
  final int? insertionScore;
  final String? aspirationResult;
  final double? aspirationDuration;
  final String? motionSmoothness;
  final double? finalWithdrawalAngle;
  final int? withdrawalScore;
  final String? correspondenceResult;
  final double? angularDelta;

  LiveSessionModel({
    required this.studentName,
    required this.studentEmail,
    required this.injectionType,
    required this.targetAngle,
    required this.phase,
    required this.liveAngle,
    this.finalInsertionAngle,
    this.insertionScore,
    this.aspirationResult,
    this.aspirationDuration,
    this.motionSmoothness,
    this.finalWithdrawalAngle,
    this.withdrawalScore,
    this.correspondenceResult,
    this.angularDelta,
  });

  factory LiveSessionModel.fromMap(Map<String, dynamic> data) {
    return LiveSessionModel(
      studentName: data['studentName'] ?? '',
      studentEmail: data['studentEmail'] ?? '',
      injectionType: data['injectionType'] ?? 'IM',
      targetAngle: (data['targetAngle'] ?? 90).toDouble(),
      phase: data['phase'] ?? 'waiting',
      liveAngle: (data['liveAngle'] ?? 0).toDouble(),
      finalInsertionAngle: data['finalInsertionAngle']?.toDouble(),
      insertionScore: data['insertionScore'],
      aspirationResult: data['aspirationResult'],
      aspirationDuration: data['aspirationDuration']?.toDouble(),
      motionSmoothness: data['motionSmoothness'],
      finalWithdrawalAngle: data['finalWithdrawalAngle']?.toDouble(),
      withdrawalScore: data['withdrawalScore'],
      correspondenceResult: data['correspondenceResult'],
      angularDelta: data['angularDelta']?.toDouble(),
    );
  }
}

class LiveSessionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Starts a new live session by overwriting the instructor's live document.
  Future<void> startSession({
    required String instructorId,
    required String studentName,
    required String studentEmail,
    required String injectionType,
    required double targetAngle,
  }) async {
    await _db.collection('live_sessions').doc(instructorId).set({
      'studentName': studentName,
      'studentEmail': studentEmail,
      'injectionType': injectionType,
      'targetAngle': targetAngle,
      'phase': 'waiting',
      'liveAngle': 0.0,
      'finalInsertionAngle': null,
      'insertionScore': null,
      'aspirationResult': null,
      'aspirationDuration': null,
      'motionSmoothness': null,
      'finalWithdrawalAngle': null,
      'withdrawalScore': null,
      'correspondenceResult': null,
      'angularDelta': null,
    });
  }

  /// Watches the live session state for both nodes.
  Stream<LiveSessionModel?> watchSession(String instructorId) {
    return _db
        .collection('live_sessions')
        .doc(instructorId)
        .snapshots()
        .map((snap) =>
            snap.exists ? LiveSessionModel.fromMap(snap.data()!) : null);
  }

  /// Updates the phase. Called by the Remote Control node.
  Future<void> updatePhase(String instructorId, String phase) async {
    await _db.collection('live_sessions').doc(instructorId).update({
      'phase': phase,
    });
  }

  /// Pushes the live angle. Called by the Camera node at ~2Hz.
  Future<void> updateLiveAngle(String instructorId, double angle) async {
    await _db.collection('live_sessions').doc(instructorId).update({
      'liveAngle': angle,
    });
  }

  /// Saves insertion metrics. Called by Camera node when phase changes.
  Future<void> saveInsertionMetrics(String instructorId, double angle, int score) async {
    await _db.collection('live_sessions').doc(instructorId).update({
      'finalInsertionAngle': angle,
      'insertionScore': score,
    });
  }

  /// Saves aspiration metrics.
  Future<void> saveAspirationMetrics(String instructorId, String result, double duration, String smoothness) async {
    await _db.collection('live_sessions').doc(instructorId).update({
      'aspirationResult': result,
      'aspirationDuration': duration,
      'motionSmoothness': smoothness,
    });
  }

  /// Saves withdrawal metrics.
  Future<void> saveWithdrawalMetrics(String instructorId, double angle, int score, String correspondence, double delta) async {
    await _db.collection('live_sessions').doc(instructorId).update({
      'finalWithdrawalAngle': angle,
      'withdrawalScore': score,
      'correspondenceResult': correspondence,
      'angularDelta': delta,
    });
  }

  /// Clears the session entirely.
  Future<void> clearSession(String instructorId) async {
    await _db.collection('live_sessions').doc(instructorId).delete();
  }
}
