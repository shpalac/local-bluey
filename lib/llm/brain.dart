import 'llm_provider.dart';
import 'tools.dart';

/// The modular brain: keeps the conversation, injects the tool system prompt,
/// and splits each reply into what Bluey says and what Bluey does.
class Brain {
  Brain({required this.provider, List<LlmMessage>? history})
    : _history = history ?? [LlmMessage('system', buildSystemPrompt())];

  final LlmProvider provider;
  final List<LlmMessage> _history;

  List<LlmMessage> get history => List.unmodifiable(_history);

  /// Sends the user's words (transcribed speech) and returns Bluey's reply.
  Future<BrainReply> ask(
    String userText, {
    List<String> images = const [],
  }) async {
    _history.add(LlmMessage('user', userText, images: images));
    final raw = await provider.chat(_history);
    final parsed = parseAssistantReply(raw);
    _history.add(LlmMessage('assistant', raw));
    return BrainReply(spoken: parsed.spoken, toolCall: parsed.toolCall);
  }

  /// Feeds a tool result back so the model can react to what it saw/did.
  Future<BrainReply> toolResult(
    String toolName,
    String result, {
    List<String> images = const [],
  }) async {
    _history.add(
      LlmMessage('tool', 'Result of $toolName:\n$result', images: images),
    );
    final raw = await provider.chat(_history);
    final parsed = parseAssistantReply(raw);
    _history.add(LlmMessage('assistant', raw));
    return BrainReply(spoken: parsed.spoken, toolCall: parsed.toolCall);
  }

  void reset() {
    _history
      ..clear()
      ..add(LlmMessage('system', buildSystemPrompt()));
  }
}

class BrainReply {
  const BrainReply({required this.spoken, this.toolCall});

  /// What Bluey says out loud / shows in the bubble.
  final String spoken;

  /// What Bluey does next, if anything.
  final ToolCall? toolCall;
}
