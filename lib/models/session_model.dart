import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/aspiration_outcome.dart';

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
  final String aspirationResult; // "No Bleeding" | "Bleeding Detected" (or legacy "Not Detected" / "Correct")
  final int aspirationScore; // 1–5
  final bool? bleedingObserved; // null = not recorded
  final double? aspirationAngleDrift;
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
  final String aiFeedbackText; // feedback text shown to students (AI draft until instructor edits it)
  final String aiFeedbackOriginal; // untouched AI draft, written once at generation, never changed
  final String feedbackStatus; // "Pending" | "Released" | "Feedback Generation Failed"
  final Timestamp? releaseTimestamp;
  final String instructorNote;
  final bool flagged;
  final String? aiValidationStatus; // "Passed" | "Auto-corrected" | "Template Fallback"
  final List<String>? aiValidationNotes;

  // Snapshots
  final String? insertionImageBase64;
  final String? aspirationImageBase64;
  final String? withdrawalImageBase64;

  final bool isPractice;

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
    required this.aspirationScore,
    this.bleedingObserved,
    this.aspirationAngleDrift,
    required this.aspirationDuration,
    required this.motionSmoothness,
    required this.withdrawalAngle,
    required this.withdrawalScore,
    required this.correspondenceResult,
    required this.angularDelta,
    required this.overallScore,
    required this.aiFeedbackText,
    this.aiFeedbackOriginal = '',
    required this.feedbackStatus,
    this.releaseTimestamp,
    required this.instructorNote,
    required this.flagged,
    this.aiValidationStatus,
    this.aiValidationNotes,
    this.insertionImageBase64,
    this.aspirationImageBase64,
    this.withdrawalImageBase64,
    this.isPractice = false,
  });

  factory SessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    String? rawSection = data['sectionName'] as String?;
    if (rawSection != null && rawSection.contains('_')) {
      rawSection = rawSection.split('_').first;
    }

    final rawAspirationResult = data['aspirationResult'] as String? ?? 'Not Detected';
    final parsedScore = data['aspirationScore'] as int? ??
        AspirationOutcome.parse(rawAspirationResult).score;

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
      aspirationResult: rawAspirationResult,
      aspirationScore: parsedScore,
      bleedingObserved: data['bleedingObserved'] as bool?,
      aspirationAngleDrift: (data['aspirationAngleDrift'] as num?)?.toDouble(),
      aspirationDuration: (data['aspirationDuration'] as num?)?.toDouble() ?? 0.0,
      motionSmoothness: data['motionSmoothness'] as String? ?? 'N/A',
      withdrawalAngle: (data['withdrawalAngle'] as num?)?.toDouble() ?? 0.0,
      withdrawalScore: data['withdrawalScore'] as int? ?? 1,
      correspondenceResult: data['correspondenceResult'] as String? ?? 'Deviates',
      angularDelta: (data['angularDelta'] as num?)?.toDouble() ?? 0.0,
      overallScore: data['overallScore'] as int? ?? 1,
      aiFeedbackText: data['aiFeedbackText'] as String? ?? '',
      aiFeedbackOriginal: data['aiFeedbackOriginal'] as String? ?? (data['aiFeedbackText'] as String? ?? ''),
      feedbackStatus: data['feedbackStatus'] as String? ?? 'Pending',
      releaseTimestamp: data['releaseTimestamp'] as Timestamp?,
      instructorNote: data['instructorNote'] as String? ?? '',
      flagged: data['flagged'] as bool? ?? false,
      aiValidationStatus: data['aiValidationStatus'] as String? ?? 'Passed',
      aiValidationNotes: (data['aiValidationNotes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      insertionImageBase64: data['insertionImageBase64'] as String?,
      aspirationImageBase64: data['aspirationImageBase64'] as String?,
      withdrawalImageBase64: data['withdrawalImageBase64'] as String?,
      isPractice: data['isPractice'] as bool? ?? (rawSection == 'Practice' || data['partnerName'] == 'Self-Practice'),
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
        'aspirationScore': aspirationScore,
        if (bleedingObserved != null) 'bleedingObserved': bleedingObserved,
        if (aspirationAngleDrift != null) 'aspirationAngleDrift': aspirationAngleDrift,
        'aspirationDuration': aspirationDuration,
        'motionSmoothness': motionSmoothness,
        'withdrawalAngle': withdrawalAngle,
        'withdrawalScore': withdrawalScore,
        'correspondenceResult': correspondenceResult,
        'angularDelta': angularDelta,
        'overallScore': overallScore,
        'aiFeedbackText': aiFeedbackText,
        'aiFeedbackOriginal': aiFeedbackOriginal.isNotEmpty ? aiFeedbackOriginal : aiFeedbackText,
        'feedbackStatus': feedbackStatus,
        if (releaseTimestamp != null) 'releaseTimestamp': releaseTimestamp,
        'instructorNote': instructorNote,
        'flagged': flagged,
        if (aiValidationStatus != null) 'aiValidationStatus': aiValidationStatus,
        if (aiValidationNotes != null) 'aiValidationNotes': aiValidationNotes,
        if (insertionImageBase64 != null) 'insertionImageBase64': insertionImageBase64,
        if (aspirationImageBase64 != null) 'aspirationImageBase64': aspirationImageBase64,
        if (withdrawalImageBase64 != null) 'withdrawalImageBase64': withdrawalImageBase64,
        'isPractice': isPractice,
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
    int? aspirationScore,
    bool? bleedingObserved,
    double? aspirationAngleDrift,
    double? aspirationDuration,
    String? motionSmoothness,
    double? withdrawalAngle,
    int? withdrawalScore,
    String? correspondenceResult,
    double? angularDelta,
    int? overallScore,
    String? aiFeedbackText,
    String? aiFeedbackOriginal,
    String? feedbackStatus,
    Timestamp? releaseTimestamp,
    String? instructorNote,
    bool? flagged,
    String? aiValidationStatus,
    List<String>? aiValidationNotes,
    String? insertionImageBase64,
    String? aspirationImageBase64,
    String? withdrawalImageBase64,
    bool? isPractice,
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
      aspirationScore: aspirationScore ?? this.aspirationScore,
      bleedingObserved: bleedingObserved ?? this.bleedingObserved,
      aspirationAngleDrift: aspirationAngleDrift ?? this.aspirationAngleDrift,
      aspirationDuration: aspirationDuration ?? this.aspirationDuration,
      motionSmoothness: motionSmoothness ?? this.motionSmoothness,
      withdrawalAngle: withdrawalAngle ?? this.withdrawalAngle,
      withdrawalScore: withdrawalScore ?? this.withdrawalScore,
      correspondenceResult: correspondenceResult ?? this.correspondenceResult,
      angularDelta: angularDelta ?? this.angularDelta,
      overallScore: overallScore ?? this.overallScore,
      aiFeedbackText: aiFeedbackText ?? this.aiFeedbackText,
      aiFeedbackOriginal: aiFeedbackOriginal ?? this.aiFeedbackOriginal,
      feedbackStatus: feedbackStatus ?? this.feedbackStatus,
      releaseTimestamp: releaseTimestamp ?? this.releaseTimestamp,
      instructorNote: instructorNote ?? this.instructorNote,
      flagged: flagged ?? this.flagged,
      aiValidationStatus: aiValidationStatus ?? this.aiValidationStatus,
      aiValidationNotes: aiValidationNotes ?? this.aiValidationNotes,
      insertionImageBase64: insertionImageBase64 ?? this.insertionImageBase64,
      aspirationImageBase64: aspirationImageBase64 ?? this.aspirationImageBase64,
      withdrawalImageBase64: withdrawalImageBase64 ?? this.withdrawalImageBase64,
      isPractice: isPractice ?? this.isPractice,
    );
  }
}
