import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirrors the Firestore `sessions/{sessionId}` document schema.
class SessionModel {
  final String sessionId;
  final String userId;
  final Timestamp timestamp;
  final String injectionType; // "IM" | "SubQ" | "IV" | "ID"

  // Insertion
  final double insertionAngle;
  final int insertionScore; // 1–5

  // Aspiration
  final String aspirationResult; // "Correct" | "Incorrect" | "Not Detected"
  final double aspirationDuration; // seconds
  final String motionSmoothness; // "Good" | "Low"

  // Withdrawal
  final double withdrawalAngle;
  final int withdrawalScore; // 1–5

  // Correspondence
  final String correspondenceResult; // "Matches" | "Deviates"
  final double angularDelta;

  // Overall
  final int overallScore; // 1–5

  // Feedback
  final String aiFeedbackText; // original Llama 3.3 output — never overwritten
  final String feedbackStatus; // "Pending" | "Released" | "Feedback Generation Failed"
  final Timestamp? releaseTimestamp;
  final String instructorNote;
  final bool flagged;

  const SessionModel({
    required this.sessionId,
    required this.userId,
    required this.timestamp,
    required this.injectionType,
    required this.insertionAngle,
    required this.insertionScore,
    required this.aspirationResult,
    required this.aspirationDuration,
    required this.motionSmoothness,
    required this.withdrawalAngle,
    required this.withdrawalScore,
    required this.correspondenceResult,
    required this.angularDelta,
    required this.overallScore,
    required this.aiFeedbackText,
    required this.feedbackStatus,
    this.releaseTimestamp,
    required this.instructorNote,
    required this.flagged,
  });

  factory SessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SessionModel(
      sessionId: doc.id,
      userId: data['userId'] as String,
      timestamp: data['timestamp'] as Timestamp,
      injectionType: data['injectionType'] as String,
      insertionAngle: (data['insertionAngle'] as num).toDouble(),
      insertionScore: data['insertionScore'] as int,
      aspirationResult: data['aspirationResult'] as String,
      aspirationDuration: (data['aspirationDuration'] as num).toDouble(),
      motionSmoothness: data['motionSmoothness'] as String,
      withdrawalAngle: (data['withdrawalAngle'] as num).toDouble(),
      withdrawalScore: data['withdrawalScore'] as int,
      correspondenceResult: data['correspondenceResult'] as String,
      angularDelta: (data['angularDelta'] as num).toDouble(),
      overallScore: data['overallScore'] as int,
      aiFeedbackText: data['aiFeedbackText'] as String? ?? '',
      feedbackStatus: data['feedbackStatus'] as String,
      releaseTimestamp: data['releaseTimestamp'] as Timestamp?,
      instructorNote: data['instructorNote'] as String? ?? '',
      flagged: data['flagged'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'timestamp': timestamp,
        'injectionType': injectionType,
        'insertionAngle': insertionAngle,
        'insertionScore': insertionScore,
        'aspirationResult': aspirationResult,
        'aspirationDuration': aspirationDuration,
        'motionSmoothness': motionSmoothness,
        'withdrawalAngle': withdrawalAngle,
        'withdrawalScore': withdrawalScore,
        'correspondenceResult': correspondenceResult,
        'angularDelta': angularDelta,
        'overallScore': overallScore,
        'aiFeedbackText': aiFeedbackText,
        'feedbackStatus': feedbackStatus,
        'releaseTimestamp': releaseTimestamp,
        'instructorNote': instructorNote,
        'flagged': flagged,
      };
}
