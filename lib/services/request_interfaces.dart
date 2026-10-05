import 'dart:io';

import '../llm/brain.dart';
import '../llm/tools.dart';
import 'settings_store.dart';
import 'stt.dart';
import 'tool_executor.dart';

/// Narrow seams between the request runner (#135) and the concrete
/// services, so the loop can run against fakes in tests.

abstract class BrainLike {
  Future<BrainReply> askStreaming(
    String userText, {
    void Function(String partialSpoken)? onToken,
  });
  Future<BrainReply> toolResult(
    String toolName,
    String result, {
    List<String> images,
  });
}

abstract class GateLike {
  bool get killed;
  int get generation;
  Future<bool> authorize(String tool, Map<String, dynamic> arguments);
}

abstract class ExecutorLike {
  Future<ToolResult> execute(ToolCall call);
}

abstract class SpeechLike {
  Future<List<int>> synthesize(String text, BrainSettings settings);
  Future<void> playBytes(List<int> bytes);
}

/// Same Future-based final-transcript contract as before; partial results
/// are reserved for later streaming work (#200). Settings are STT-scoped
/// since #196, not the brain's.
abstract class TranscriberLike {
  Future<String> transcribe(File audio, SttSettings settings);
}
