import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';
import 'ollama_provider.dart' show LlmException;
import 'tools.dart';

/// Any OpenAI-compatible REST endpoint: OpenRouter, LocalAI, OpenCode, etc.
/// Uses POST {baseUrl}/chat/completions.
class OpenAiCompatibleProvider extends LlmProvider {
  @override
  bool get supportsNativeTools => true;
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

  /// Screenshots ride along as image_url parts so multimodal models
  /// (gpt-4o, gemini, llama-vision) actually see the screen.
  Map<String, dynamic> _toApi(LlmMessage m) {
    if (m.images.isEmpty) return {'role': m.role, 'content': m.content};
    return {
      'role': m.role,
      'content': [
        {'type': 'text', 'text': m.content},
        for (final image in m.images)
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$image'},
          },
      ],
    };
  }

  @override
  Future<String> chat(List<LlmMessage> messages) async {
    final headers = {'Content-Type': 'application/json'};
    if (apiKey != null && apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: headers,
      body: jsonEncode({'model': model, 'messages': messages.map(_toApi)}),
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

  @override
  Future<LlmResponse> chatWithTools(List<LlmMessage> messages) async {
    final headers = {'Content-Type': 'application/json'};
    if (apiKey != null && apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: headers,
      body: jsonEncode({
        'model': model,
        'tools': kToolsAsFunctions(),
        'messages': messages.map(_toApi),
      }),
    );
    if (response.statusCode != 200) {
      throw LlmException(
        'OpenAI-compatible ${response.statusCode}: ${response.body}',
      );
    }
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final choices = body['choices'] as List? ?? const [];
    if (choices.isEmpty) return const LlmResponse('');
    final message = Map<String, dynamic>.from(
      (choices.first as Map)['message'] as Map? ?? const {},
    );
    final toolCalls = message['tool_calls'] as List? ?? const [];
    ToolCall? call;
    if (toolCalls.isNotEmpty) {
      final fn = Map<String, dynamic>.from(
        (toolCalls.first as Map)['function'] as Map? ?? const {},
      );
      final name = fn['name'] as String?;
      if (name != null) {
        final args = fn['arguments'];
        call = ToolCall(
          name,
          args is String
              ? Map<String, dynamic>.from(
                  jsonDecode(args.isEmpty ? '{}' : args) as Map,
                )
              : args is Map
              ? Map<String, dynamic>.from(args)
              : {},
        );
      }
    }
    return LlmResponse(
      message['content'] as String? ?? '',
      toolCall: call,
    );
  }

  @override
  Stream<String> chatStream(List<LlmMessage> messages) async* {
    final headers = {'Content-Type': 'application/json'};
    if (apiKey != null && apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    final request = http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
    request.headers.addAll(headers);
    request.body = jsonEncode({
      'model': model,
      'stream': true,
      'messages': messages.map(_toApi),
    });
    final streamed = await _client.send(request);
    if (streamed.statusCode != 200) {
      throw LlmException('OpenAI-compatible ${streamed.statusCode}');
    }
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      for (final line in chunk.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') return;
        try {
          final body = Map<String, dynamic>.from(jsonDecode(payload) as Map);
          final choices = body['choices'] as List? ?? const [];
          if (choices.isEmpty) continue;
          final delta = Map<String, dynamic>.from(
            (choices.first as Map)['delta'] as Map? ?? const {},
          );
          final content = delta['content'] as String? ?? '';
          if (content.isNotEmpty) yield content;
        } catch (_) {
          // Partial JSON line - skip.
        }
      }
    }
  }
}
