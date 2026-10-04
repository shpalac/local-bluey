import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';

/// Local Ollama backend: POST {baseUrl}/api/chat with streaming disabled.
class OllamaProvider extends LlmProvider {
  OllamaProvider({
    this.baseUrl = 'http://localhost:11434',
    this.model = 'llama3.2',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String model;
  final http.Client _client;

  @override
  String get name => 'Ollama ($model)';

  @override
  Future<String> chat(List<LlmMessage> messages) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': model,
        'stream': false,
        'messages': messages.map((m) => m.toJson()).toList(),
      }),
    );
    if (response.statusCode != 200) {
      throw LlmException('Ollama ${response.statusCode}: ${response.body}');
    }
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final message = Map<String, dynamic>.from(
      body['message'] as Map? ?? const {},
    );
    return message['content'] as String? ?? '';
  }
}

class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}
