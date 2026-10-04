import 'dart:convert';

import 'tools.dart';

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
}

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
