import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = 'https://detect.roboflow.com/infer/workflows/veincarmell-pangilinan-cit-edu/find-syringe-arm-and-needle';
  final response = await http.post(
    Uri.parse(url),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'api_key': 'J9jW40Es9tFmhUzmXpMe',
      'inputs': {
        'image': {'type': 'url', 'value': 'https://upload.wikimedia.org/wikipedia/commons/4/4d/Syringe_and_needle.jpg'}
      }
    }),
  );
  print(response.statusCode);
  print(response.body);
}
