import 'dart:io';

import '../llm/brain.dart';
import '../llm/tools.dart';
import 'settings_store.dart';
import 'stt.dart';
import 'tool_executor.dart';

/// Narrow seams between the request runner (#135) and the concrete
/// services, so the loop can run against fakes in tests.

abstract class BrainLike {
  /// Sends user text; [onToken] gets partial replies as they stream.
  Future<BrainReply> askStreaming(
    String userText, {
    void Function(String partialSpoken)? onToken,
  });

  /// Feeds a tool's [result] back and gets the follow-up reply.
  Future<BrainReply> toolResult(
    String toolName,
    String result, {
    List<String> images,
  });
}

/// Authorization check before a tool runs (#87 kill switch included).
abstract class GateLike {
  bool get killed;
  int get generation;

  /// Whether [tool] may run with [arguments] right now.
  Future<bool> authorize(String tool, Map<String, dynamic> arguments);
}

/// Runs one tool call against the host.
abstract class ExecutorLike {
  /// Executes [call] and returns its result for the brain.
  Future<ToolResult> execute(ToolCall call);
}

/// Text-to-speech seam.
abstract class SpeechLike {
  /// Renders [text] to audio bytes with the configured TTS settings.
  Future<List<int>> synthesize(String text, BrainSettings settings);

  /// Plays previously synthesized [bytes].
  Future<void> playBytes(List<int> bytes);
}

/// Same Future-based final-transcript contract as before; partial results
/// are reserved for later streaming work (#200). Settings are STT-scoped
/// since #196, not the brain's.
abstract class TranscriberLike {
  /// Transcribes [audio] with [settings]; throws [SttException] on
  /// failure.
  Future<String> transcribe(File audio, SttSettings settings);
}
