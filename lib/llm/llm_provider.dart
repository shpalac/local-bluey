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
      final parsed = _callFromJson(trimmed);
      if (parsed != null) {
        call = parsed;
        continue;
      }
    }
    buffer.writeln(line);
  }
  return (spoken: buffer.toString().trim(), toolCall: call);
}

/// Strips the stray tag models leave behind, such as a closing `tool_call`
/// marker with an invisible character inside it, which would otherwise be
/// spoken to the user.
String _stripToolMarkup(String text) =>
    text.replaceAll(_residualMarkup, '').trim();

/// Anything tag-shaped that still mentions a tool call. Bounded so ordinary
/// prose containing angle brackets is left alone.
final RegExp _residualMarkup = RegExp(r'<[^<>]{0,40}tool_call[^<>]{0,12}>');

/// One tool call lifted out of model text, and the text with it removed.
typedef InlineToolCallResult = ({String spoken, ToolCall? toolCall});

/// Reads a tool call the model wrote into `content` instead of the provider's
/// structured `tool_calls` channel, and returns the remaining prose.
///
/// Small local models do this constantly and in several shapes, even when the
/// request carried a `tools` array. Ollama answers qwen3-coder with
/// `<function=look_at_screen>` in `content` and a null `tool_calls`, so a
/// provider that reads only the structured channel silently drops the call and
/// the model then narrates an action it never performed.
///
/// Recognised, in priority order:
///   `<|tool_call|>{"name":..,"arguments":..}<|end_tool_call|>`  (Llama 3.x)
///   `<function=name>{..}</function>`                             (Qwen 2.5/3)
///   `<function=name>{..}` ending the reply, unterminated        (observed)
///   `{"tool":..,"arguments":..}`                                  (our own prompt)
///
/// The name must appear in [kToolNames]. A reply is untrusted input, and these
/// calls drive the real cursor and keyboard, so an unknown name is dropped
/// rather than guessed at.
InlineToolCallResult extractInlineToolCall(String raw) {
  // A shape we recognise but a name we reject still has to leave the prose,
  // or Bluey reads the markup out loud. Each branch drops its own span on the
  // way to the next one, so a hallucinated name never hides a real call.
  var text = raw;

  // Llama 3.x carries the name inside the JSON payload, not in a tag.
  final llama = _llamaCall.firstMatch(text);
  if (llama != null) {
    final call = _callFromNameAndArgs(llama.namedGroup('json'));
    if (call != null) {
      return (spoken: _stripToolMarkup(_drop(text, llama)), toolCall: call);
    }
    text = _drop(text, llama);
  }
  // Qwen 2.5/3 puts the name in the tag. The closing tag is optional at the
  // end of a truncated generation, which is the only place it is unbracketed;
  // mid-prose an unclosed tag is ambiguous, so it stays in the speech.
  final tagged = _qwenCall.firstMatch(text);
  if (tagged != null) {
    final name = tagged.namedGroup('name');
    if (name != null && kToolNames.contains(name)) {
      return (
        spoken: _stripToolMarkup(_drop(text, tagged)),
        toolCall: ToolCall(name, _arguments(tagged.namedGroup('args'))),
      );
    }
    text = _drop(text, tagged);
  }
  // Qwen's per-parameter XML form: <function=f><parameter=k>v</parameter></function>
  final params = _qwenParams.firstMatch(text);
  if (params != null) {
    final name = params.namedGroup('name');
    if (name != null && kToolNames.contains(name)) {
      return (
        spoken: _stripToolMarkup(_drop(text, params)),
        toolCall: ToolCall(name, _parameters(params.namedGroup('body'))),
      );
    }
    text = _drop(text, params);
  }
  // Our own documented convention, anywhere in the text rather than only as a
  // whole line: models like to prefix it with "Sure, one moment".
  final own = _ownCall.firstMatch(text);
  if (own != null) {
    // This shape keys on "tool", not "name".
    final call = _callFromJson(own.group(0) ?? '');
    if (call != null) {
      return (spoken: _stripToolMarkup(_drop(text, own)), toolCall: call);
    }
    text = _drop(text, own);
  }
  return (spoken: _stripToolMarkup(text), toolCall: null);
}

/// Removes [match] from [text]. A space rather than nothing, so a span that
/// sat between two words does not weld them together.
String _drop(String text, Match match) =>
    text.replaceRange(match.start, match.end, ' ');

/// `<function=f><parameter=k>v</parameter>...</function>`, the per-parameter
/// spelling qwen3-coder uses when it has arguments to carry.
final RegExp _qwenParams = RegExp(
  r'<function=(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*>'
  r'(?<body>(?:(?!</function>)[\s\S])*?)'
  r'</function>',
  dotAll: true,
);

final RegExp _qwenParameter = RegExp(
  r'<parameter=(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*>(?<value>[\s\S]*?)</parameter>',
  dotAll: true,
);

/// Collects `<parameter=k>v</parameter>` pairs, coercing obvious scalars so a
/// grid coordinate arrives as a number rather than the text "500".
Map<String, dynamic> _parameters(String? body) {
  final out = <String, dynamic>{};
  for (final m in _qwenParameter.allMatches(body ?? '')) {
    final key = m.namedGroup('key');
    if (key == null) continue;
    out[key] = _scalar(m.namedGroup('value') ?? '');
  }
  return out;
}

/// A parameter value is JSON when it parses as a JSON scalar, else plain text.
Object? _scalar(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  try {
    return jsonDecode(text);
  } catch (_) {
    return text;
  }
}

/// Reads `{"name":..,"arguments":..}` and validates the name.
ToolCall? _callFromNameAndArgs(String? source) {
  final text = source?.trim() ?? '';
  if (text.isEmpty) return null;
  try {
    final map = Map<String, dynamic>.from(jsonDecode(text) as Map);
    final name = map['name'];
    if (name is! String || !kToolNames.contains(name)) return null;
    final args = map['arguments'];
    return ToolCall(
      name,
      args is Map ? Map<String, dynamic>.from(args) : const {},
    );
  } catch (_) {
    return null;
  }
}

/// Decodes a tool-call argument blob, tolerating the empty case.
Map<String, dynamic> _arguments(String? blob) {
  final text = blob?.trim() ?? '';
  if (text.isEmpty) return const {};
  try {
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  } catch (_) {
    // Prose where JSON was expected: call with no arguments rather than
    // dropping it, so a no-argument tool like look_at_screen still runs.
    return const {};
  }
}

/// Shared by the {"tool":..} convention in [parseAssistantReply].
ToolCall? _callFromJson(String source) {
  try {
    final map = Map<String, dynamic>.from(jsonDecode(source) as Map);
    final name = map['tool'];
    if (name is! String || !kToolNames.contains(name)) return null;
    final args = map['arguments'];
    return ToolCall(
      name,
      args is Map ? Map<String, dynamic>.from(args) : const {},
    );
  } catch (_) {
    // Not valid JSON - treat as spoken text.
    return null;
  }
}

/// `<|tool_call|>{"name":"look_at_screen","arguments":{}}<|end_tool_call|>`.
/// The closing token is tolerated in both the piped and slashed spellings.
final RegExp _llamaCall = RegExp(
  r'<\|tool_call\|>\s*(?<json>\{.*?\})\s*</?\|?end_tool_call\|?>',
  dotAll: true,
);

/// `<function=look_at_screen>{"target_id":"W1"}</function>`, and the same tag
/// truncated before its arguments or closing tag.
final RegExp _qwenCall = RegExp(
  r'<function=(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*>'
  r'(?<args>\{.*?\})?\s*(?:</function>|(?=\s*$))',
  dotAll: true,
);

/// `{"tool":"look_at_screen","arguments":{}}` - one level of nesting, which is
/// what an "arguments" object needs.
final RegExp _ownCall = RegExp(
  r'\{[^{}]*"tool"\s*:\s*"[A-Za-z_][A-Za-z0-9_]*"[^{}]*'
  r'(?:\{[^{}]*\}[^{}]*)*\}',
  dotAll: true,
);
