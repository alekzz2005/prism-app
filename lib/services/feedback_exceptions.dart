/// Thrown when the OpenRouter API times out after both attempts.
class FeedbackTimeoutException implements Exception {
  const FeedbackTimeoutException();
  @override
  String toString() => 'FeedbackTimeoutException: OpenRouter request timed out.';
}

/// Thrown when OpenRouter returns a non-200 status.
class FeedbackApiException implements Exception {
  final int statusCode;
  final String body;
  const FeedbackApiException(this.statusCode, this.body);
  @override
  String toString() => 'FeedbackApiException($statusCode): $body';
}
