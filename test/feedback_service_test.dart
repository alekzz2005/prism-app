import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/models/session_model.dart';
import 'package:prism_app/services/feedback_evidence.dart';
import 'package:prism_app/services/feedback_exceptions.dart';
import 'package:prism_app/services/feedback_service.dart';
import 'package:prism_app/services/openrouter_api_client.dart';

class FailingOpenRouterApiClient extends OpenRouterApiClient {
  final Exception exceptionToThrow;

  FailingOpenRouterApiClient(this.exceptionToThrow);

  @override
  Future<String> generateFeedback(String prompt, {FeedbackEvidence? evidence}) async {
    throw exceptionToThrow;
  }
}

class EmptyOpenRouterApiClient extends OpenRouterApiClient {
  @override
  Future<String> generateFeedback(String prompt, {FeedbackEvidence? evidence}) async {
    return '   ';
  }
}

SessionModel _createTestSession({bool isPractice = false}) {
  return SessionModel(
    sessionId: 'session_test_123',
    userId: 'student@example.com',
    studentName: 'Student Name',
    timestamp: Timestamp.now(),
    injectionType: 'IM',
    insertionAngle: 89.0,
    insertionScore: 5,
    aspirationResult: 'No Bleeding',
    aspirationScore: 5,
    aspirationDuration: 5.0,
    motionSmoothness: 'Good',
    withdrawalAngle: 89.0,
    withdrawalScore: 5,
    angularDelta: 0.0,
    correspondenceResult: 'Matches',
    overallScore: 5,
    aiFeedbackText: '',
    feedbackStatus: isPractice ? 'Released' : 'Pending',
    instructorNote: '',
    flagged: false,
    isPractice: isPractice,
  );
}

void main() {
  group('FeedbackService Fallback on AI Failure', () {
    test('timeout error populates deterministic fallback and Failed status for official session', () async {
      final client = FailingOpenRouterApiClient(const FeedbackTimeoutException());
      final service = FeedbackService(client: client);
      final session = _createTestSession(isPractice: false);

      final result = await service.generateFeedbackForSession(session);

      expect(result.aiFeedbackText.isNotEmpty, isTrue);
      expect(result.aiFeedbackOriginal, equals(result.aiFeedbackText));
      expect(result.aiValidationStatus, equals('Template Fallback'));
      expect(result.aiValidationNotes, contains('ai_unavailable'));
      expect(result.feedbackStatus, equals('Feedback Generation Failed'));
    });

    test('timeout error keeps Released status for practice session', () async {
      final client = FailingOpenRouterApiClient(const FeedbackTimeoutException());
      final service = FeedbackService(client: client);
      final session = _createTestSession(isPractice: true);

      final result = await service.generateFeedbackForSession(session);

      expect(result.aiFeedbackText.isNotEmpty, isTrue);
      expect(result.aiFeedbackOriginal, equals(result.aiFeedbackText));
      expect(result.aiValidationStatus, equals('Template Fallback'));
      expect(result.aiValidationNotes, contains('ai_unavailable'));
      expect(result.feedbackStatus, equals('Released'));
    });

    test('API exception triggers deterministic fallback', () async {
      final client = FailingOpenRouterApiClient(const FeedbackApiException(500, 'Server Error'));
      final service = FeedbackService(client: client);
      final session = _createTestSession(isPractice: false);

      final result = await service.generateFeedbackForSession(session);

      expect(result.aiFeedbackText.isNotEmpty, isTrue);
      expect(result.aiFeedbackOriginal, equals(result.aiFeedbackText));
      expect(result.aiValidationStatus, equals('Template Fallback'));
      expect(result.aiValidationNotes, contains('ai_unavailable'));
      expect(result.feedbackStatus, equals('Feedback Generation Failed'));
    });

    test('empty AI reply triggers deterministic fallback', () async {
      final client = EmptyOpenRouterApiClient();
      final service = FeedbackService(client: client);
      final session = _createTestSession(isPractice: false);

      final result = await service.generateFeedbackForSession(session);

      expect(result.aiFeedbackText.isNotEmpty, isTrue);
      expect(result.aiFeedbackOriginal, equals(result.aiFeedbackText));
      expect(result.aiValidationStatus, equals('Template Fallback'));
      expect(result.aiValidationNotes, contains('ai_unavailable'));
      expect(result.feedbackStatus, equals('Feedback Generation Failed'));
    });

    test('FeedbackLabels returns correct student labels for official, practice, and fallback', () {
      expect(
        FeedbackLabels.studentFeedbackLabel(isPractice: false),
        equals('AI-assisted feedback, reviewed by your instructor'),
      );
      expect(
        FeedbackLabels.studentFeedbackLabel(isPractice: true, isTemplateFallback: false),
        equals('AI guide for practice, not reviewed by an instructor'),
      );
      expect(
        FeedbackLabels.studentFeedbackLabel(isPractice: true, isTemplateFallback: true),
        equals('Automatic summary from your recorded metrics (AI unavailable). Not reviewed by an instructor.'),
      );
    });
  });
}
