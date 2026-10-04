import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';
import 'retry.dart';
import '../services/egress_monitor.dart';
import 'tools.dart';

/// Local Ollama backend: POST {baseUrl}/api/chat with streaming disabled.
class OllamaProvider extends LlmProvider {
  @override
  bool get supportsNativeTools => true;
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
    return withRetry(() async {
      final payload = jsonEncode({
        'model': model,
        'stream': false,
        'messages': messages.map((m) => m.toJson()).toList(),
      });
      final response = await _client.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      unawaited(
        EgressMonitor.instance.record(baseUrl, 'brain', payload.length),
      );
      if (response.statusCode != 200) {
        throw LlmException('Ollama ${response.statusCode}: ${response.body}');
      }
      final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      final message = Map<String, dynamic>.from(
        body['message'] as Map? ?? const {},
      );
      return message['content'] as String? ?? '';
    });
  }

  @override
  Future<LlmResponse> chatWithTools(List<LlmMessage> messages) async {
    return withRetry(() async {
      final payload = jsonEncode({
        'model': model,
        'stream': false,
        'tools': kToolsAsFunctions(),
        'messages': messages.map((m) => m.toJson()).toList(),
      });
      final response = await _client.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      unawaited(
        EgressMonitor.instance.record(baseUrl, 'brain', payload.length),
      );
      if (response.statusCode != 200) {
        throw LlmException('Ollama ${response.statusCode}: ${response.body}');
      }
      final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      final message = Map<String, dynamic>.from(
        body['message'] as Map? ?? const {},
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
            args is Map
                ? Map<String, dynamic>.from(args)
                : args is String
                ? Map<String, dynamic>.from(
                    jsonDecode(args.isEmpty ? '{}' : args) as Map,
                  )
                : {},
          );
        }
      }
      return LlmResponse(message['content'] as String? ?? '', toolCall: call);
    });
  }

  @override
  Stream<String> chatStream(List<LlmMessage> messages) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'model': model,
      'stream': true,
      'messages': messages.map((m) => m.toJson()).toList(),
    });
    final streamed = await _client.send(request);
    if (streamed.statusCode != 200) {
      throw LlmException('Ollama ${streamed.statusCode}');
    }
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      for (final line in chunk.split('\n')) {
        if (line.trim().isEmpty) continue;
        try {
          final body = Map<String, dynamic>.from(jsonDecode(line) as Map);
          final message = Map<String, dynamic>.from(
            body['message'] as Map? ?? const {},
          );
          final content = message['content'] as String? ?? '';
          if (content.isNotEmpty) yield content;
        } catch (_) {
          // Partial JSON line - skip.
        }
      }
    }
  }
}

class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}
