import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const _apiKey = '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';
  const _baseUrl = 'https://openrouter.ai/api/v1/chat/completions';
  const _model = 'meta-llama/llama-3.3-70b-instruct';

  try {
    final response = await http.post(
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
          {'role': 'system', 'content': 'Test'},
          {'role': 'user', 'content': 'Test'}
        ],
        'max_tokens': 300,
        'temperature': 0.7,
      }),
    );
    print(response.statusCode);
    print(response.body);
  } catch (e) {
    print(e);
  }
}
