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

  // Snapshots
  final String? insertionImageBase64;
  final String? aspirationImageBase64;
  final String? withdrawalImageBase64;

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
    this.insertionImageBase64,
    this.aspirationImageBase64,
    this.withdrawalImageBase64,
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
      insertionImageBase64: data['insertionImageBase64'] as String?,
      aspirationImageBase64: data['aspirationImageBase64'] as String?,
      withdrawalImageBase64: data['withdrawalImageBase64'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'studentName': studentName,
        'timestamp': timestamp,
        'injectionType': injectionType,
        if (sectionName != null) 'sectionName': sectionName,
        if (partnerName != null) 'partnerName': partnerName,
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
        if (releaseTimestamp != null) 'releaseTimestamp': releaseTimestamp,
        'instructorNote': instructorNote,
        'flagged': flagged,
        if (insertionImageBase64 != null) 'insertionImageBase64': insertionImageBase64,
        if (aspirationImageBase64 != null) 'aspirationImageBase64': aspirationImageBase64,
        if (withdrawalImageBase64 != null) 'withdrawalImageBase64': withdrawalImageBase64,
      };

  SessionModel copyWith({
    String? sessionId,
    String? userId,
    String? studentName,
    Timestamp? timestamp,
    String? injectionType,
    String? sectionName,
    String? partnerName,
    double? insertionAngle,
    int? insertionScore,
    String? aspirationResult,
    double? aspirationDuration,
    String? motionSmoothness,
    double? withdrawalAngle,
    int? withdrawalScore,
    String? correspondenceResult,
    double? angularDelta,
    int? overallScore,
    String? aiFeedbackText,
    String? feedbackStatus,
    Timestamp? releaseTimestamp,
    String? instructorNote,
    bool? flagged,
    String? insertionImageBase64,
    String? aspirationImageBase64,
    String? withdrawalImageBase64,
  }) {
    return SessionModel(
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      studentName: studentName ?? this.studentName,
      timestamp: timestamp ?? this.timestamp,
      injectionType: injectionType ?? this.injectionType,
      sectionName: sectionName ?? this.sectionName,
      partnerName: partnerName ?? this.partnerName,
      insertionAngle: insertionAngle ?? this.insertionAngle,
      insertionScore: insertionScore ?? this.insertionScore,
      aspirationResult: aspirationResult ?? this.aspirationResult,
      aspirationDuration: aspirationDuration ?? this.aspirationDuration,
      motionSmoothness: motionSmoothness ?? this.motionSmoothness,
      withdrawalAngle: withdrawalAngle ?? this.withdrawalAngle,
      withdrawalScore: withdrawalScore ?? this.withdrawalScore,
      correspondenceResult: correspondenceResult ?? this.correspondenceResult,
      angularDelta: angularDelta ?? this.angularDelta,
      overallScore: overallScore ?? this.overallScore,
      aiFeedbackText: aiFeedbackText ?? this.aiFeedbackText,
      feedbackStatus: feedbackStatus ?? this.feedbackStatus,
      releaseTimestamp: releaseTimestamp ?? this.releaseTimestamp,
      instructorNote: instructorNote ?? this.instructorNote,
      flagged: flagged ?? this.flagged,
      insertionImageBase64: insertionImageBase64 ?? this.insertionImageBase64,
      aspirationImageBase64: aspirationImageBase64 ?? this.aspirationImageBase64,
      withdrawalImageBase64: withdrawalImageBase64 ?? this.withdrawalImageBase64,
    );
  }
}
