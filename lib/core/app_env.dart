import 'package:flutter/foundation.dart';

/// Centralized environment configuration loaded through `--dart-define` or `--dart-define-from-file`.
class AppEnv {
  AppEnv._();

  /// OpenRouter API Key for Llama 3.3 70B evaluation.
  static const String openRouterApiKey =
      String.fromEnvironment('OPENROUTER_API_KEY');

  /// Roboflow API Key for syringe/needle detection.
  static const String roboflowApiKey =
      String.fromEnvironment('ROBOFLOW_API_KEY');

  /// Roboflow Hosted Workflow URL for inference.
  static const String roboflowWorkflowUrl =
      String.fromEnvironment('ROBOFLOW_WORKFLOW_URL');

  /// Mock feedback flag to bypass external LLM calls.
  static const bool useMockFeedback = bool.fromEnvironment(
    'USE_MOCK_FEEDBACK',
    defaultValue: false,
  );

  /// Validates environment keys and logs warnings when required keys are empty.
  static void validate() {
    if (useMockFeedback) {
      debugPrint(
        '[AppEnv] Mock mode enabled (USE_MOCK_FEEDBACK=true). External API keys not required.',
      );
      return;
    }
    if (openRouterApiKey.isEmpty) {
      debugPrint(
        '[AppEnv WARNING] OPENROUTER_API_KEY is empty. AI feedback generation will fail unless USE_MOCK_FEEDBACK=true.',
      );
    }
    if (roboflowApiKey.isEmpty) {
      debugPrint(
        '[AppEnv WARNING] ROBOFLOW_API_KEY is empty. Roboflow CV detection will fail.',
      );
    }
    if (roboflowWorkflowUrl.isEmpty) {
      debugPrint(
        '[AppEnv WARNING] ROBOFLOW_WORKFLOW_URL is empty. Roboflow CV detection will fail.',
      );
    }
  }
}
