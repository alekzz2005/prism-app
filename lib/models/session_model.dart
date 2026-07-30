import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirrors the Firestore `sessions/{sessionId}` document schema.
class SessionModel {
  final String sessionId;
  final String userId;
  final String studentName;
  final Timestamp timestamp;
  final String injectionType; // "IM"
  final String? sectionName; // e.g. "Section 3A"
  final String? partnerName;

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
    required this.studentName,
    required this.timestamp,
    required this.injectionType,
    this.sectionName,
    this.partnerName,
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
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    String? rawSection = data['sectionName'] as String?;
    if (rawSection != null && rawSection.contains('_')) {
      rawSection = rawSection.split('_').first;
    }

    return SessionModel(
      sessionId: doc.id,
      userId: data['userId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? 'Unknown Student',
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      injectionType: data['injectionType'] as String? ?? 'IM',
      sectionName: rawSection,
      partnerName: data['partnerName'] as String?,
      insertionAngle: (data['insertionAngle'] as num?)?.toDouble() ?? 0.0,
      insertionScore: data['insertionScore'] as int? ?? 1,
      aspirationResult: data['aspirationResult'] as String? ?? 'Not Detected',
      aspirationDuration: (data['aspirationDuration'] as num?)?.toDouble() ?? 0.0,
      motionSmoothness: data['motionSmoothness'] as String? ?? 'Low',
      withdrawalAngle: (data['withdrawalAngle'] as num?)?.toDouble() ?? 0.0,
      withdrawalScore: data['withdrawalScore'] as int? ?? 1,
      correspondenceResult: data['correspondenceResult'] as String? ?? 'Deviates',
      angularDelta: (data['angularDelta'] as num?)?.toDouble() ?? 0.0,
      overallScore: data['overallScore'] as int? ?? 1,
      aiFeedbackText: data['aiFeedbackText'] as String? ?? '',
      feedbackStatus: data['feedbackStatus'] as String? ?? 'Pending',
      releaseTimestamp: data['releaseTimestamp'] as Timestamp?,
      instructorNote: data['instructorNote'] as String? ?? '',
      flagged: data['flagged'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'studentName': studentName,
        'timestamp': timestamp,
        'injectionType': injectionType,
        'sectionName': sectionName,
        'partnerName': partnerName,
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
