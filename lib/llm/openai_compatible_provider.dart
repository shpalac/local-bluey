import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';
import 'ollama_provider.dart' show LlmException;

/// Any OpenAI-compatible REST endpoint: OpenRouter, LocalAI, OpenCode, etc.
/// Uses POST {baseUrl}/chat/completions.
class OpenAiCompatibleProvider extends LlmProvider {
  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.model,
    this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// e.g. http://localhost:1234/v1 or https://openrouter.ai/api/v1
  final String baseUrl;
  final String model;
  final String? apiKey;
  final http.Client _client;

  @override
  String get name => 'OpenAI-compatible ($model)';

  @override
  Future<String> chat(List<LlmMessage> messages) async {
    final headers = {'Content-Type': 'application/json'};
    if (apiKey != null && apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: headers,
      body: jsonEncode({
        'model': model,
        'messages': messages
            .map((m) => {'role': m.role, 'content': m.content})
            .toList(),
      }),
    );
    if (response.statusCode != 200) {
      throw LlmException(
        'OpenAI-compatible ${response.statusCode}: ${response.body}',
      );
    }
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final choices = body['choices'] as List? ?? const [];
    if (choices.isEmpty) return '';
    final message = Map<String, dynamic>.from(
      (choices.first as Map)['message'] as Map? ?? const {},
    );
    return message['content'] as String? ?? '';
  }
}
