import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';
import 'retry.dart';
import '../services/egress_monitor.dart';
import 'ollama_provider.dart' show LlmException;
import 'tools.dart';
import 'stream_records.dart';

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
    return withRetry(() async {
      final headers = {'Content-Type': 'application/json'};
      if (apiKey != null && apiKey!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }
      final payload = jsonEncode({
        'model': model,
        'messages': messages.map(_toApi).toList(),
      });
      final response = await _client.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: headers,
        body: payload,
      );
      unawaited(
        EgressMonitor.instance.record(baseUrl, 'brain', payload.length),
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
    });
  }

  @override
  Future<LlmResponse> chatWithTools(List<LlmMessage> messages) async {
    return withRetry(() async {
      final headers = {'Content-Type': 'application/json'};
      if (apiKey != null && apiKey!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }
      final payload = jsonEncode({
        'model': model,
        'tools': kToolsAsFunctions(),
        'messages': messages.map(_toApi).toList(),
      });
      final response = await _client.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: headers,
        body: payload,
      );
      unawaited(
        EgressMonitor.instance.record(baseUrl, 'brain', payload.length),
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
      return LlmResponse(message['content'] as String? ?? '', toolCall: call);
    });
  }

  @override
  Stream<String> chatStream(List<LlmMessage> messages) async* {
    final headers = {'Content-Type': 'application/json'};
    if (apiKey != null && apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/chat/completions'),
    );
    request.headers.addAll(headers);
    request.body = jsonEncode({
      'model': model,
      'stream': true,
      'messages': messages.map(_toApi).toList(),
    });
    final streamed = await _client.send(request);
    if (streamed.statusCode != 200) {
      await streamed.stream.listen((_) {}, onError: (Object _) {}).cancel();
      throw LlmException('OpenAI-compatible ${streamed.statusCode}');
    }
    await for (final payload in sseRecords(streamed.stream)) {
      if (payload.trim() == '[DONE]') return;
      if (payload.isEmpty) continue;
      final body = streamObject(payload);
      if (body.containsKey('error')) {
        throw LlmException('OpenAI-compatible stream backend error');
      }
      final choices = body['choices'];
      if (choices == null) continue;
      if (choices is! List) {
        throw LlmException('Malformed OpenAI-compatible stream choices');
      }
      if (choices.isEmpty) continue;
      final first = choices.first;
      if (first is! Map) {
        throw LlmException('Malformed OpenAI-compatible stream choice');
      }
      final delta = first['delta'];
      if (delta != null && delta is! Map) {
        throw LlmException('Malformed OpenAI-compatible stream delta');
      }
      final content = delta is Map ? delta['content'] : null;
      if (content != null && content is! String) {
        throw LlmException('Malformed OpenAI-compatible stream content');
      }
      if (content is String && content.isNotEmpty) yield content;
    }
  }
}
