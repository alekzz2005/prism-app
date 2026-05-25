import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'feedback_exceptions.dart';

/// Set this to true to skip the real API call and return mock feedback.
/// Useful for testing the full session flow without an API key.
const bool kUseMockFeedback = bool.fromEnvironment(
  'USE_MOCK_FEEDBACK',
  defaultValue: false,
);

/// Mock feedback returned when [kUseMockFeedback] is true.
const String _mockFeedbackText =
    'Your insertion angle of 88.2° was well within the ±5° tolerance for an IM injection, '
    'earning a 4/5 on the CIT-U rubric. Aspiration technique was correctly performed with '
    'smooth plunger retraction over 2.1 seconds, demonstrating good motor control.\n\n'
    'Your withdrawal angle deviated 8.2° from your insertion path, which falls outside the '
    'acceptable range and suggests lateral wrist movement during needle removal. Focus on '
    'keeping your elbow stationary and withdrawing along the same vector as insertion to '
    'minimise tissue trauma.\n\n'
    'Before your next RD, practise the full sequence on a phantom model 5 times, using a '
    'wrist-pivot technique: lock your elbow against your body and rotate only at the wrist '
    'for both insertion and withdrawal. This builds the muscle memory needed for consistent angles.';

/// HTTP client for the OpenRouter Llama 3.3 70B (free tier) API.
///
/// **To use with a real key**, run flutter with:
/// ```
/// flutter run --dart-define-from-file=.env.json
/// ```
///
/// **To test without a key** (mock mode):
/// ```
/// flutter run --dart-define=USE_MOCK_FEEDBACK=true
/// ```
class OpenRouterApiClient {
  static const String _apiKey = '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';

  static const String _baseUrl =
      'https://openrouter.ai/api/v1/chat/completions';

  static const String _model =
      'meta-llama/llama-3.3-70b-instruct';

  static const _systemPrompt =
      'You are PRISM, an AI clinical nursing evaluator. '
      'You are given ONLY numerical metrics from a parenteral injection return-demonstration (RD). '
      'You did NOT observe the procedure — you are analyzing data values only. '
      'Be strictly objective: if a score is low (1-2/5), state it needs significant improvement — do NOT say it was done well. '
      'If a score is high (4-5/5), acknowledge the strong performance with the specific numbers. '
      'Reply in EXACTLY 3 short paragraphs, no headers, no bullet points: '
      '(1) Objectively summarize which metrics met or exceeded the target, citing the exact angles and scores, '
      '(2) Objectively identify which metrics fell short of the target, citing the deviation and what it indicates clinically, '
      '(3) Provide one specific, actionable practice recommendation based on the weakest metric. '
      'Tone: professional, direct, constructive, factual. Never fabricate observations. Max 150 words total.';

  /// Sends [prompt] to Llama 3.3 70B free and returns the response text.
  ///
  /// If [kUseMockFeedback] is true, returns [_mockFeedbackText] immediately.
  /// Throws [FeedbackTimeoutException] on timeout, [FeedbackApiException] on non-200.
  Future<String> generateFeedback(String prompt) async {
    // ── Mock mode for testing without API key ──
    if (kUseMockFeedback) {
      await Future.delayed(const Duration(seconds: 2)); // simulate latency
      return _mockFeedbackText;
    }

    if (_apiKey.isEmpty) {
      throw FeedbackApiException(
          0,
          'OPENROUTER_API_KEY is not set. Run with:\n'
          '  flutter run --dart-define-from-file=.env.json\n'
          'Or for mock mode:\n'
          '  flutter run --dart-define=USE_MOCK_FEEDBACK=true');
    }

    Exception? lastError;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _post(prompt).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw const FeedbackTimeoutException(),
        );

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final content =
              (body['choices'] as List).first['message']['content'];
          return content as String;
        }

        throw FeedbackApiException(response.statusCode, response.body);
      } on FeedbackTimeoutException catch (e) {
        lastError = e;
        if (attempt == 0) {
          await Future.delayed(const Duration(seconds: 2));
        }
      } on FeedbackApiException {
        rethrow; // don't retry API errors — they won't self-heal
      }
    }
    throw lastError!;
  }

  Future<http.Response> _post(String userPrompt) => http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://prism.cit-u.edu.ph',
          'X-Title': 'PRISM',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'max_tokens': 300,
          'temperature': 0.7,
        }),
      );
}
