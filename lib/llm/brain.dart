import 'llm_provider.dart';
import 'tools.dart';

/// The modular brain: keeps the conversation, injects the tool system prompt,
/// and splits each reply into what Bluey says and what Bluey does.
class Brain {
  Brain({required this.provider, List<LlmMessage>? history})
    : _history = history ?? [LlmMessage('system', buildSystemPrompt())];

  /// Conversation never grows past this many messages; the system prompt
  /// always stays. Older turns are dropped oldest-first.
  static const maxHistory = 40;

  /// Screenshots are huge: only the most recent exchanges keep theirs.
  static const keepImagesInLast = 2;

  final LlmProvider provider;
  final List<LlmMessage> _history;

  List<LlmMessage> get history => List.unmodifiable(_history);

  void _boundedAdd(LlmMessage message) {
    _history.add(message);
    // Prune images from anything older than the last exchanges.
    for (var i = 1; i < _history.length - keepImagesInLast; i++) {
      final m = _history[i];
      if (m.images.isNotEmpty) {
        _history[i] = LlmMessage(m.role, m.content);
      }
    }
    while (_history.length > maxHistory) {
      _history.removeAt(1); // keep the system prompt at index 0
    }
  }

  /// Sends the user's words (transcribed speech) and returns Bluey's reply.
  Future<BrainReply> ask(
    String userText, {
    List<String> images = const [],
  }) async {
    _boundedAdd(LlmMessage('user', userText, images: images));
    final raw = await provider.chat(_history);
    final parsed = parseAssistantReply(raw);
    _boundedAdd(LlmMessage('assistant', raw));
    return BrainReply(spoken: parsed.spoken, toolCall: parsed.toolCall);
  }

  /// Streaming ask: [onToken] gets raw fragments as they arrive; the
  /// returned reply is identical to [ask]. Tool-call JSON lines are held
  /// back from the token stream.
  Future<BrainReply> askStreaming(
    String userText, {
    List<String> images = const [],
    void Function(String partialSpoken)? onToken,
  }) async {
    _boundedAdd(LlmMessage('user', userText, images: images));
    final raw = await _streamCollect(onToken);
    final parsed = parseAssistantReply(raw);
    _boundedAdd(LlmMessage('assistant', raw));
    return BrainReply(spoken: parsed.spoken, toolCall: parsed.toolCall);
  }

  Future<String> _streamCollect(
    void Function(String partialSpoken)? onToken,
  ) async {
    final buffer = StringBuffer();
    await for (final fragment in provider.chatStream(_history)) {
      buffer.write(fragment);
      onToken?.call(buffer.toString());
    }
    return buffer.toString();
  }

  /// Feeds a tool result back so the model can react to what it saw/did.
  Future<BrainReply> toolResult(
    String toolName,
    String result, {
    List<String> images = const [],
  }) async {
    _boundedAdd(
      LlmMessage('tool', 'Result of $toolName:\n$result', images: images),
    );
    final raw = await provider.chat(_history);
    final parsed = parseAssistantReply(raw);
    _boundedAdd(LlmMessage('assistant', raw));
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
