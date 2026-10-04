import 'dart:convert';

import 'tools.dart';

/// One model turn: spoken text plus an optional structured tool call.
class LlmResponse {
  const LlmResponse(this.text, {this.toolCall});

  final String text;
  final ToolCall? toolCall;
}

class LlmMessage {
  const LlmMessage(this.role, this.content, {this.images = const []});

  /// "system", "user", "assistant" or "tool".
  final String role;
  final String content;

  /// Base64 JPEGs (e.g. screenshots for multimodal models).
  final List<String> images;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'role': role, 'content': content};
    if (images.isNotEmpty) map['images'] = images;
    return map;
  }
}

/// A pluggable brain backend. Implementations: Ollama (local REST) and any
/// OpenAI-compatible endpoint (OpenRouter, LocalAI, OpenCode, etc.).
abstract class LlmProvider {
  String get name;

  /// Sends the conversation and returns the assistant's raw text reply,
  /// which may contain a {"tool": ...} JSON block per the system prompt.
  Future<String> chat(List<LlmMessage> messages);

  /// Streaming variant: yields raw reply fragments as they arrive.
  /// Default falls back to the whole reply at once.
  Stream<String> chatStream(List<LlmMessage> messages) async* {
    yield await chat(messages);
  }

  /// Native function calling. Providers that support it override this;
  /// the default parses a JSON block out of the text reply.
  Future<LlmResponse> chatWithTools(List<LlmMessage> messages) async {
    final raw = await chat(messages);
    final parsed = parseAssistantReply(raw);
    return LlmResponse(parsed.spoken, toolCall: parsed.toolCall);
  }

  /// Whether the system prompt should skip the JSON-block instructions.
  bool get supportsNativeTools => false;
}

/// Bluey's visible working states, shown as a status chip.
enum BlueyStatus { listening, thinking, acting, error, offline }

/// Splits a raw assistant reply into spoken text and at most one tool call.
({String spoken, ToolCall? toolCall}) parseAssistantReply(String raw) {
  final buffer = StringBuffer();
  ToolCall? call;
  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (call == null && trimmed.startsWith('{') && trimmed.contains('"tool"')) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(trimmed) as Map);
        if (map['tool'] is String) {
          call = ToolCall(
            map['tool'] as String,
            Map<String, dynamic>.from((map['arguments'] as Map?) ?? const {}),
          );
          continue;
        }
      } catch (_) {
        // Not valid JSON - treat as spoken text.
      }
    }
    buffer.writeln(line);
  }
  return (spoken: buffer.toString().trim(), toolCall: call);
}
