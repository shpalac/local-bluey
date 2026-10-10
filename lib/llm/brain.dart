import '../services/request_interfaces.dart';
import 'llm_provider.dart';
import 'tools.dart';

/// The modular brain: keeps the conversation, injects the tool system prompt,
/// and splits each reply into what Bluey says and what Bluey does.
class Brain implements BrainLike {
  Brain({required this.provider, List<LlmMessage>? history, String? persona})
    : _persona = persona,
      _history = history != null
          ? List.of(history)
          : [
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
  final String? _persona;
  int _generation = 0;
  Future<void>? _summary;

  List<LlmMessage> _snapshot(Iterable<LlmMessage> messages) =>
      List.unmodifiable(
        messages.map(
          (m) => LlmMessage(
            m.role,
            m.content,
            images: List.unmodifiable(m.images),
          ),
        ),
      );

  /// Turns that overflowed the window but were not summarized yet.
  final List<LlmMessage> _overflow = [];

  /// The running memory. Rebuilt whenever more turns overflow.
  String? memory;

  /// Read-only view of the conversation as sent to the provider.
  List<LlmMessage> get history => _snapshot(_history);

  void _boundedAdd(LlmMessage message) {
    _history.add(
      LlmMessage(
        message.role,
        message.content,
        images: List.unmodifiable(message.images),
      ),
    );
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
  Future<void> _consolidateMemory(int gen) {
    if (gen != _generation || _overflow.isEmpty) return Future.value();
    if (_summary != null) return _summary!;
    late Future<void> current;
    current = _summarize(gen).whenComplete(() {
      if (identical(_summary, current)) _summary = null;
    });
    return _summary = current;
  }

  Future<void> _summarize(int gen) async {
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
      updated = await provider.chat(_snapshot(prompt));
    } catch (_) {
      return; // retry on the next call; overflow stays buffered
    }
    if (gen != _generation || updated.trim().isEmpty) return;
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
  /// Reset during entered work returns an empty reply with no tool, not abort.
  Future<BrainReply> ask(
    String userText, {
    List<String> images = const [],
  }) async {
    final gen = _generation;
    _boundedAdd(LlmMessage('user', userText, images: images));
    try {
      await _consolidateMemory(gen);
      if (gen != _generation) return const BrainReply(spoken: '');
      final response = await provider.chatWithTools(_snapshot(_history));
      if (gen != _generation) return const BrainReply(spoken: '');
      _boundedAdd(LlmMessage('assistant', response.text));
      return BrainReply(spoken: response.text, toolCall: response.toolCall);
    } catch (_) {
      if (gen != _generation) return const BrainReply(spoken: '');
      rethrow;
    }
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
    final gen = _generation;
    _boundedAdd(LlmMessage('user', userText, images: images));
    try {
      final raw = await _streamCollect(gen, onToken);
      if (gen != _generation) return const BrainReply(spoken: '');
      final parsed = parseAssistantReply(raw);
      _boundedAdd(LlmMessage('assistant', raw));
      return BrainReply(spoken: parsed.spoken, toolCall: parsed.toolCall);
    } catch (_) {
      if (gen != _generation) return const BrainReply(spoken: '');
      rethrow;
    }
  }

  Future<String> _streamCollect(
    int gen,
    void Function(String partialSpoken)? onToken,
  ) async {
    final buffer = StringBuffer();
    await for (final fragment in provider.chatStream(_snapshot(_history))) {
      if (gen != _generation) return '';
      buffer.write(fragment);
      onToken?.call(buffer.toString());
      if (gen != _generation) return '';
    }
    return buffer.toString();
  }

  /// Feeds a tool result back so the model can react to what it saw/did.
  /// Reset invalidates the reply, not an already-performed external action.
  @override
  Future<BrainReply> toolResult(
    String toolName,
    String result, {
    List<String> images = const [],
  }) async {
    final gen = _generation;
    _boundedAdd(
      LlmMessage('tool', 'Result of $toolName:\n$result', images: images),
    );
    try {
      final response = await provider.chatWithTools(_snapshot(_history));
      if (gen != _generation) return const BrainReply(spoken: '');
      _boundedAdd(LlmMessage('assistant', response.text));
      return BrainReply(spoken: response.text, toolCall: response.toolCall);
    } catch (_) {
      if (gen != _generation) return const BrainReply(spoken: '');
      rethrow;
    }
  }

  /// Clears history, overflow and memory back to the configured system persona.
  /// Invalidates entered replies/tokens/tools/summaries; stale methods return an
  /// empty reply without tools. Not provider cancellation or retrospective undo.
  void reset() {
    _generation++;
    _summary = null;
    _overflow.clear();
    memory = null;
    _history
      ..clear()
      ..add(
        LlmMessage(
          'system',
          buildSystemPrompt(
            nativeTools: provider.supportsNativeTools,
            persona: _persona,
          ),
        ),
      );
  }
}

/// One turn of the brain: what Bluey says, plus the tool call to run.
class BrainReply {
  const BrainReply({required this.spoken, this.toolCall});

  /// What Bluey says out loud / shows in the bubble.
  final String spoken;

  /// What Bluey does next, if anything.
  final ToolCall? toolCall;
}
