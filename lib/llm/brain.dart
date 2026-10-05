import '../services/request_interfaces.dart';
import 'llm_provider.dart';
import 'tools.dart';

/// The modular brain: keeps the conversation, injects the tool system prompt,
/// and splits each reply into what Bluey says and what Bluey does.
class Brain implements BrainLike {
  Brain({required this.provider, List<LlmMessage>? history, String? persona})
    : _history =
          history ??
          [
            LlmMessage(
              'system',
              buildSystemPrompt(
                nativeTools: provider.supportsNativeTools,
                persona: persona,
              ),
            ),
          ];

  /// Conversation never grows past this many messages; the system prompt
  /// always stays. Older turns are folded into a running memory summary
  /// instead of being dropped (#60).
  static const maxHistory = 40;

  /// Prefix marking the synthesized memory message at history index 1.
  static const memoryPrefix = 'Conversation memory so far:';

  /// Screenshots are huge: only the most recent exchanges keep theirs.
  static const keepImagesInLast = 2;

  /// The backend that answers chat calls (Ollama or OpenAI-compatible).
  final LlmProvider provider;
  final List<LlmMessage> _history;

  /// Turns that overflowed the window but were not summarized yet.
  final List<LlmMessage> _overflow = [];

  /// The running memory. Rebuilt whenever more turns overflow.
  String? memory;

  /// Read-only view of the conversation as sent to the provider.
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
      // Keep the system prompt and the memory message; evict the oldest turn.
      final idx = _history.length > 1 && _isMemoryMessage(_history[1]) ? 2 : 1;
      _overflow.add(_history.removeAt(idx));
    }
  }

  bool _isMemoryMessage(LlmMessage m) =>
      m.role == 'system' && m.content.startsWith(memoryPrefix);

  /// Folds overflowed turns into the running memory before the next call.
  /// Failures keep the overflow buffered so nothing is lost silently.
  Future<void> _consolidateMemory() async {
    if (_overflow.isEmpty) return;
    final batch = List<LlmMessage>.from(_overflow);
    final turns = batch.map((m) => '${m.role}: ${m.content}').join('\n');
    final prompt = [
      LlmMessage(
        'system',
        'You compress conversation logs into a durable memory. Keep facts, '
            'names, decisions, preferences and open threads. Drop filler. '
            'Reply with the updated memory only, in the log\'s language.',
      ),
      if (memory != null) LlmMessage('user', 'Existing memory:\n$memory'),
      LlmMessage('user', 'New turns to fold in:\n$turns'),
    ];
    final String updated;
    try {
      updated = await provider.chat(prompt);
    } catch (_) {
      return; // retry on the next call; overflow stays buffered
    }
    if (updated.trim().isEmpty) return;
    _overflow.removeRange(0, batch.length);
    memory = updated;
    final memMessage = LlmMessage('system', '$memoryPrefix\n$updated');
    if (_history.length > 1 && _isMemoryMessage(_history[1])) {
      _history[1] = memMessage;
    } else {
      _history.insert(1, memMessage);
    }
  }

  /// Sends the user's words (transcribed speech) and returns Bluey's reply.
  Future<BrainReply> ask(
    String userText, {
    List<String> images = const [],
  }) async {
    _boundedAdd(LlmMessage('user', userText, images: images));
    await _consolidateMemory();
    final response = await provider.chatWithTools(_history);
    _boundedAdd(LlmMessage('assistant', response.text));
    return BrainReply(spoken: response.text, toolCall: response.toolCall);
  }

  /// Streaming ask: [onToken] gets raw fragments as they arrive; the
  /// returned reply is identical to [ask]. Tool-call JSON lines are held
  /// back from the token stream.
  @override
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
  @override
  Future<BrainReply> toolResult(
    String toolName,
    String result, {
    List<String> images = const [],
  }) async {
    _boundedAdd(
      LlmMessage('tool', 'Result of $toolName:\n$result', images: images),
    );
    final response = await provider.chatWithTools(_history);
    _boundedAdd(LlmMessage('assistant', response.text));
    return BrainReply(spoken: response.text, toolCall: response.toolCall);
  }

  void reset() {
    _history
      ..clear()
      ..add(
        LlmMessage(
          'system',
          buildSystemPrompt(nativeTools: provider.supportsNativeTools),
        ),
      );
  }
}

class BrainReply {
  const BrainReply({required this.spoken, this.toolCall});

  /// What Bluey says out loud / shows in the bubble.
  final String spoken;

  /// What Bluey does next, if anything.
  final ToolCall? toolCall;
}
