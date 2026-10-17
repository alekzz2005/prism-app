import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'feedback_exceptions.dart';
import 'feedback_evidence.dart';
import 'deterministic_feedback_builder.dart';

/// Set this to true to skip the real API call and return mock feedback.
/// Useful for testing the full session flow without an API key.
const bool kUseMockFeedback = bool.fromEnvironment(
  'USE_MOCK_FEEDBACK',
  defaultValue: false,
);

/// Mock feedback returned when [kUseMockFeedback] is true.
const String _mockFeedbackText =
    'During the insertion phase, your syringe angle of 88.2° was well within the ±5° tolerance for an IM injection, earning a 4/5 on the CIT-U rubric with good control and confidence.\n\n'
    'During aspiration, the technique was executed properly over the full duration with no blood return detected, safely confirming needle placement within muscle tissue.\n\n'
    'During withdrawal, your angle deviated by 8.2° from the initial insertion trajectory (scoring 3/5). This indicates wrist pivot upon needle removal, which increases patient discomfort and risk of tissue trauma.\n\n'
    'For your next return-demonstration, practice locking your wrist against your forearm to pull straight back along the exact same 90° vector used during insertion.';

/// HTTP client for the OpenRouter Llama 3.3 70B (free tier) API.
///
/// **To use with a real key**, ensure `OPENROUTER_API_KEY` is set in your `.env` file.
///
/// **To test without a key** (mock mode):
/// ```
/// flutter run --dart-define=USE_MOCK_FEEDBACK=true
/// ```

class OpenRouterApiClient {
  static String get _apiKey => dotenv.env['OPENROUTER_API_KEY'] ?? '';

  static const String _baseUrl =
      'https://openrouter.ai/api/v1/chat/completions';

  static const List<String> _models = [
    'meta-llama/llama-3.3-70b-instruct:free',
    'meta-llama/llama-3.3-70b-instruct',
    'google/gemini-2.0-flash-lite-preview-02-05:free',
    'deepseek/deepseek-r1:free',
  ];

  static const _systemPrompt =
      'You are PRISM, an AI clinical nursing evaluator for Intramuscular (IM) injection return-demonstrations (RDs) at CIT-U.\n\n'
      'MANDATORY CLINICAL VALIDATION RULES:\n'
      '1. Use ONLY numbers provided in the payload. Do not invent, extrapolate, or mention any numbers not in the payload (except the 90° standard and 1-5 rubric scores).\n'
      '2. Never state a time or duration unless one is explicitly given in the payload. If duration is not recorded, do not mention duration, seconds, or timing.\n'
      '3. Blood presence is based ONLY on what the instructor confirmed, never "detected by the camera". If aspiration outcome was not recorded, do not comment on blood presence.\n'
      '4. Rubric expectations (e.g. 90° dart-like insertion, aspirate and observe for blood, withdraw at the same angle) may be mentioned as the standard, but never claimed as observed unless a metric supports it.\n'
      '5. Do not mention wrist/hand steadiness, speed, smoothness, or neuromuscular terms unless in the payload.\n\n'
      'STRUCTURE (EXACTLY 4 PARAGRAPHS, <= 175 WORDS TOTAL, NO HEADERS, NO BULLETS):\n'
      'Paragraph 1: Evaluate insertion angle against the 90° standard (±5° tolerance) and insertion score.\n'
      'Paragraph 2: Evaluate aspiration blood check, duration (only if given), needle drift (only if given), and aspiration score.\n'
      'Paragraph 3: Evaluate withdrawal angle, angular delta, correspondence, and withdrawal score.\n'
      'Paragraph 4: Provide one specific, actionable recommendation targeting the lowest scoring step to ensure safe practice.';

  /// Sends [prompt] to Llama 3.3 70B and returns the response text.
  /// Throws [FeedbackTimeoutException] on timeout, [FeedbackApiException] on non-200.
  Future<String> generateFeedback(String prompt, {FeedbackEvidence? evidence}) async {
    if (kUseMockFeedback) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (evidence != null) {
        return DeterministicFeedbackBuilder.build(evidence);
      }
      return _mockFeedbackText;
    }

    if (_apiKey.isEmpty) {
      throw FeedbackApiException(0, 'OPENROUTER_API_KEY is not configured in .env');
    }

    Exception? lastError;
    for (final model in _models) {
      try {
        final response = await _postWithModel(prompt, model).timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw const FeedbackTimeoutException(),
        );

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          if (body.containsKey('choices') && (body['choices'] as List).isNotEmpty) {
            final content = (body['choices'] as List).first['message']['content'];
            if (content is String && content.trim().isNotEmpty) {
              return content.trim();
            }
          }
        } else {
          lastError = FeedbackApiException(response.statusCode, response.body);
        }
      } on FeedbackTimeoutException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = FeedbackApiException(0, e.toString());
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw const FeedbackApiException(500, 'Unable to generate AI feedback across available models.');
  }

  Future<http.Response> _postWithModel(String userPrompt, String model) => http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://prism.cit-u.edu.ph',
          'X-Title': 'PRISM',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'max_tokens': 300,
          'temperature': 0.7,
        }),
      );
}
