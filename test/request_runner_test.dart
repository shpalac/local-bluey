import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/brain.dart';
import 'package:local_bluey/llm/llm_provider.dart' show BlueyStatus;
import 'package:local_bluey/llm/tools.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/services/request_interfaces.dart';
import 'package:local_bluey/services/request_runner.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/services/speech.dart';
import 'package:local_bluey/services/tool_executor.dart';
import 'package:local_bluey/services/stt.dart';

class FakeBrain implements BrainLike {
  final replies = <BrainReply>[];
  final toolResults = <String>[];
  String? lastAsked;

  @override
  Future<BrainReply> askStreaming(
    String userText, {
    void Function(String partialSpoken)? onToken,
  }) async {
    lastAsked = userText;
    onToken?.call('partial');
    return replies.removeAt(0);
  }

  @override
  Future<BrainReply> toolResult(
    String toolName,
    String result, {
    List<String> images = const [],
  }) async {
    toolResults.add('$toolName|$result|${images.length}');
    return replies.removeAt(0);
  }
}

class FakeGate implements GateLike {
  bool allow = true;
  void Function()? onAuthorize;
  int authorizeCalls = 0;

  @override
  bool killed = false;
  @override
  int generation = 0;

  @override
  Future<bool> authorize(String tool, Map<String, dynamic> arguments) async {
    authorizeCalls++;
    onAuthorize?.call();
    return allow;
  }
}

class FakeExecutor implements ExecutorLike {
  ToolResult next = const ToolResult('did it');
  void Function()? onExecute;
  int calls = 0;

  @override
  Future<ToolResult> execute(ToolCall call) async {
    calls++;
    onExecute?.call();
    return next;
  }
}

class FakeSpeech implements SpeechLike {
  bool fail = false;
  int synthesized = 0;
  List<int>? played;

  @override
  Future<List<int>> synthesize(String text, BrainSettings settings) async {
    synthesized++;
    if (fail) throw SpeechException('boom');
    return [1, 2, 3];
  }

  @override
  Future<void> playBytes(List<int> bytes) async {
    played = bytes;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class FakeTranscriber implements TranscriberLike {
  String result = 'hello there';
  bool fail = false;

  @override
  Future<String> transcribe(File audio, SttSettings settings) async {
    if (fail) throw SttException(SttErrorKind.httpError, 'nope');
    return result;
  }
}

class SpyHooks extends RequestHooks {
  final bubbles = <String?>[];
  final statuses = <BlueyStatus>[];
  final faces = <Mood>[];
  final sentFaces = <Mood>[];
  final says = <String>[];

  @override
  void bubble(String? text) => bubbles.add(text);
  @override
  void status(BlueyStatus status) => statuses.add(status);
  @override
  void face(FaceState face) => faces.add(face.mood);
  @override
  void sendFace(FaceState face) => sentFaces.add(face.mood);
  @override
  void say(Packet packet, String spoken) => says.add(spoken);
}

const _settings = BrainSettings(
  backend: BrainBackend.ollama,
  baseUrl: 'http://localhost',
  model: 'm',
);

(
  RequestRunner,
  FakeBrain,
  FakeGate,
  FakeExecutor,
  FakeSpeech,
  FakeTranscriber,
  SpyHooks,
  List<List<String>>,
)
_rig({bool withBrain = true}) {
  final b = FakeBrain();
  final gate = FakeGate();
  final exec = FakeExecutor();
  final speech = FakeSpeech();
  final transcriber = FakeTranscriber();
  final hooks = SpyHooks();
  final conversation = <List<String>>[];
  final runner = RequestRunner(
    transcriber: transcriber,
    safety: gate,
    tools: exec,
    speech: speech,
    brainProvider: withBrain ? () => b : () => null,
    settingsLoader: () async => _settings,
    sttLoader: () async => const SttSettings(baseUrl: 'http://stt.local/v1'),
    matchRoutine: (_) => null,
    addToConversation: (role, text) => conversation.add([role, text]),
    currentVoice: () => 'alloy',
    hooks: hooks,
  );
  return (runner, b, gate, exec, speech, transcriber, hooks, conversation);
}

class _NoBrain implements BrainLike {
  const _NoBrain();
  @override
  Future<BrainReply> askStreaming(
    String t, {
    void Function(String p)? onToken,
  }) async => throw StateError('unused');
  @override
  Future<BrainReply> toolResult(
    String n,
    String r, {
    List<String> images = const [],
  }) async => throw StateError('unused');
}

void main() {
  final file = File('test/_runner_fake_audio.m4a');

  test('empty transcription short-circuits with a hint', () async {
    final (runner, brain, _, _, _, transcriber, hooks, conversation) = _rig();
    transcriber.result = '';
    await runner.process(file);
    expect(hooks.bubbles, contains("Didn't catch that."));
    expect(brain.lastAsked, isNull);
    expect(conversation, isEmpty);
  });

  test('no brain configured asks the user to set one up', () async {
    final (runner, _, _, _, _, _, hooks, _) = _rig(withBrain: false);
    await runner.process(file);
    expect(hooks.bubbles, contains('Set up the brain in settings first.'));
  });

  test('plain reply: conversation, bubble, face, say with audio', () async {
    final (runner, brain, _, _, speech, _, hooks, conversation) = _rig();
    brain.replies.add(const BrainReply(spoken: 'hi human'));
    await runner.process(file);
    expect(brain.lastAsked, 'hello there');
    expect(conversation, [
      ['user', 'hello there'],
      ['bluey', 'hi human'],
    ]);
    expect(hooks.bubbles, contains('hi human'));
    expect(hooks.faces, contains(Mood.talking));
    expect(hooks.says, ['hi human']);
    expect(speech.synthesized, 1);
    expect(speech.played, [1, 2, 3]);
    expect(hooks.faces.last, Mood.listening);
    expect(hooks.sentFaces.last, Mood.listening);
  });

  test('asleep companion resets to a sleepy face', () async {
    final (runner, brain, _, _, _, _, hooks, _) = _rig();
    brain.replies.add(const BrainReply(spoken: 'hi'));
    runner.awake = false;
    await runner.process(file);
    expect(hooks.faces.last, Mood.sleepy);
    expect(hooks.statuses.last, BlueyStatus.listening);
  });

  test('routine trigger expands into standing instructions (#56)', () async {
    final (runner, brain, _, _, _, _, _, _) = _rig();
    final runnerWithRoutine = RequestRunner(
      transcriber: FakeTranscriber(),
      safety: FakeGate(),
      tools: FakeExecutor(),
      speech: FakeSpeech(),
      brainProvider: () => brain,
      settingsLoader: () async => _settings,
      sttLoader: () async => const SttSettings(baseUrl: 'http://stt.local/v1'),
      matchRoutine: (_) => const Routine(
        name: 'briefing',
        trigger: 'hello',
        instructions: 'give the morning briefing',
      ),
      addToConversation: (_, _) {},
      currentVoice: () => 'alloy',
    );
    brain.replies.add(const BrainReply(spoken: 'ok'));
    await runnerWithRoutine.process(file);
    expect(
      brain.lastAsked,
      'hello there\n\n[Routine "briefing"] give the morning briefing',
    );
    expect(runner.stepTimeout, const Duration(seconds: 60));
  });

  test('denied tool is reported to the brain, not executed', () async {
    final (runner, brain, gate, exec, _, _, _, _) = _rig();
    gate.allow = false;
    brain.replies.addAll([
      BrainReply(spoken: '', toolCall: ToolCall('delete_all', {})),
      const BrainReply(spoken: 'fine, skipped'),
    ]);
    await runner.process(file);
    expect(exec.calls, 0);
    expect(brain.toolResults, ['delete_all|Denied by the user.|0']);
    expect(brain.replies, isEmpty);
  });

  test('executed tool feeds text and image back to the brain', () async {
    final (runner, brain, _, exec, _, _, _, _) = _rig();
    exec.next = const ToolResult('screenshot taken', imageBase64: 'aW1n');
    brain.replies.addAll([
      BrainReply(spoken: '', toolCall: ToolCall('screenshot', {})),
      const BrainReply(spoken: 'done'),
    ]);
    await runner.process(file);
    expect(exec.calls, 1);
    expect(brain.toolResults, ['screenshot|screenshot taken|1']);
  });

  test('max tool steps stops the loop with a note', () async {
    final (runner, brain, _, _, _, _, hooks, _) = _rig();
    for (var i = 0; i < 6; i++) {
      brain.replies.add(BrainReply(spoken: '', toolCall: ToolCall('noop', {})));
    }
    await runner.process(file);
    expect(hooks.bubbles, contains('Too many steps - stopping here.'));
    expect(brain.toolResults.length, 5);
  });

  test('kill before the tool step stops the run (#107)', () async {
    final (runner, brain, gate, exec, _, _, hooks, _) = _rig();
    gate.killed = true; // killed while the first ask was streaming
    brain.replies.add(BrainReply(spoken: '', toolCall: ToolCall('x', {})));
    await runner.process(file);
    expect(exec.calls, 0);
    expect(gate.authorizeCalls, 0);
    expect(hooks.bubbles, contains('Stopped.'));
  });

  test('kill during confirmation stops after the denial (#107)', () async {
    final (runner, brain, gate, exec, _, _, hooks, _) = _rig();
    gate.allow = false;
    gate.onAuthorize = () => gate.killed = true;
    brain.replies.add(BrainReply(spoken: '', toolCall: ToolCall('x', {})));
    await runner.process(file);
    expect(exec.calls, 0);
    expect(brain.toolResults, isEmpty);
    expect(hooks.bubbles, contains('Stopped.'));
  });

  test('generation bump (kill+resume) stops after execution (#107)', () async {
    final (runner, brain, gate, exec, _, _, hooks, _) = _rig();
    exec.onExecute = () => gate.generation++;
    brain.replies.add(BrainReply(spoken: '', toolCall: ToolCall('x', {})));
    await runner.process(file);
    expect(exec.calls, 1);
    expect(brain.toolResults, isEmpty);
    expect(hooks.bubbles, contains('Stopped.'));
  });

  test('TTS failure still says the text and notes the failure', () async {
    final (runner, brain, _, _, speech, _, hooks, _) = _rig();
    speech.fail = true;
    brain.replies.add(const BrainReply(spoken: 'spoken words'));
    await runner.process(file);
    expect(hooks.says, ['spoken words']);
    expect(speech.played, isNull);
    expect(
      hooks.bubbles.any((b) => b != null && b.contains('TTS failed')),
      isTrue,
    );
  });

  test('transcription failure surfaces an error state', () async {
    final (runner, brain, _, _, _, transcriber, hooks, _) = _rig();
    transcriber.fail = true;
    await runner.process(file);
    expect(brain.lastAsked, isNull);
    expect(hooks.statuses, contains(BlueyStatus.error));
    expect(
      hooks.bubbles.any(
        (b) => b != null && b.startsWith('Transcription failed'),
      ),
      isTrue,
    );
  });

  test('unexpected brain error surfaces an error state', () async {
    final hooks = SpyHooks();
    final failing = RequestRunner(
      transcriber: FakeTranscriber(),
      safety: FakeGate(),
      tools: FakeExecutor(),
      speech: FakeSpeech(),
      brainProvider: () => const _NoBrain(),
      settingsLoader: () async => _settings,
      matchRoutine: (_) => null,
      addToConversation: (_, _) {},
      currentVoice: () => 'alloy',
      hooks: hooks,
    );
    await failing.process(file);
    expect(hooks.statuses, contains(BlueyStatus.error));
  });
}
