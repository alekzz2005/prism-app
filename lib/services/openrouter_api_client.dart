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
const String _mockFeedbackText = '''
**Overall Performance: Good effort on your first return-demonstration!**

You demonstrated a solid understanding of injection technique fundamentals. Your insertion angle was well-controlled and your hand remained steady throughout the procedure. The aspiration step was performed with appropriate duration, which is critical for patient safety in intramuscular injections.

Areas for improvement include maintaining a more consistent withdrawal angle that mirrors your insertion angle. Your angular delta of 8.2° slightly exceeds the accepted tolerance — practice withdrawing along the same vector as insertion to minimise tissue trauma. Consider using a wrist-pivot technique to keep the needle path linear.

**Clinical tip:** Before your next RD, practice the full insertion-aspiration-withdrawal sequence on a phantom model at least 5 times, focusing specifically on keeping your elbow still during withdrawal. Consistency between insertion and withdrawal angles is a key competency marker for the CIT-U rubric.
''';

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
  static const String _apiKey =
      String.fromEnvironment('OPENROUTER_API_KEY', defaultValue: '');

  static const String _baseUrl =
      'https://openrouter.ai/api/v1/chat/completions';

  // Using the free tier model (matches the :free variant)
  static const String _model =
      'meta-llama/llama-3.3-70b-instruct:free';

  static const _systemPrompt =
      'You are a clinical nursing education evaluator. Generate structured, '
      'encouraging, and specific feedback for a nursing student\'s parenteral '
      'injection return demonstration. Include: what was done correctly, what '
      'needs improvement, and one specific tip. Keep the tone clinical but '
      'supportive. Respond in 3 short paragraphs.';

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
          'max_tokens': 500,
        }),
      );
}
