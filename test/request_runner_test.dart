import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
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
  Completer<BrainReply>? asking, reacting;
  final askEntered = Completer<void>(), resultEntered = Completer<void>();
  void Function(String)? stream;
  void Function()? onAsk, onResult;

  @override
  Future<BrainReply> askStreaming(
    String userText, {
    void Function(String partialSpoken)? onToken,
  }) async {
    lastAsked = userText;
    stream = onToken;
    if (!askEntered.isCompleted) askEntered.complete();
    onAsk?.call();
    onToken?.call('partial');
    return asking?.future ?? Future.value(replies.removeAt(0));
  }

  @override
  Future<BrainReply> toolResult(
    String toolName,
    String result, {
    List<String> images = const [],
  }) async {
    toolResults.add('$toolName|$result|${images.length}');
    if (!resultEntered.isCompleted) resultEntered.complete();
    onResult?.call();
    return reacting?.future ?? Future.value(replies.removeAt(0));
  }
}

class FakeGate implements GateLike {
  bool allow = true;
  void Function()? onAuthorize;
  int authorizeCalls = 0;
  Completer<bool>? pending;
  final entered = Completer<void>();

  @override
  bool killed = false;
  @override
  int generation = 0;

  @override
  Future<bool> authorize(String tool, Map<String, dynamic> arguments) async {
    authorizeCalls++;
    if (!entered.isCompleted) entered.complete();
    onAuthorize?.call();
    return pending?.future ?? Future.value(allow);
  }
}

class FakeExecutor implements ExecutorLike {
  ToolResult next = const ToolResult('did it');
  void Function()? onExecute;
  int calls = 0;
  Completer<ToolResult>? pending;
  final entered = Completer<void>();

  @override
  Future<ToolResult> execute(ToolCall call) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    onExecute?.call();
    return pending?.future ?? Future.value(next);
  }
}

class FakeSpeech implements SpeechLike {
  bool fail = false;
  int synthesized = 0;
  List<int>? played;
  Completer<List<int>>? pending;
  final entered = Completer<void>();
  void Function()? onSynthesize;

  @override
  Future<List<int>> synthesize(String text, BrainSettings settings) async {
    synthesized++;
    if (!entered.isCompleted) entered.complete();
    onSynthesize?.call();
    if (pending != null) return pending!.future;
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
  Future<void> Function()? onTranscribe;

  @override
  Future<String> transcribe(File audio, SttSettings settings) async {
    if (fail) throw SttException(SttErrorKind.httpError, 'nope');
    await onTranscribe?.call();
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
_rig({
  bool withBrain = true,
  Duration? jobTimeout,
  DateTime Function()? now,
  Future<void> Function(File)? deleteRecording,
  void Function()? onSettings,
}) {
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
    settingsLoader: () async {
      onSettings?.call();
      return _settings;
    },
    sttLoader: () async => const SttSettings(baseUrl: 'http://stt.local/v1'),
    matchRoutine: (_) => null,
    addToConversation: (role, text) => conversation.add([role, text]),
    currentVoice: () => 'alloy',
    hooks: hooks,
    jobTimeout: jobTimeout ?? const Duration(minutes: 3),
    now: now,
    deleteRecording: deleteRecording,
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

  test(
    'Stop during transcription discards the late transcript (#199)',
    () async {
      final (runner, brain, gate, _, _, transcriber, hooks, _) = _rig();
      transcriber.onTranscribe = () async => gate.killed = true;
      await runner.process(file);
      expect(brain.lastAsked, isNull);
      expect(hooks.bubbles, contains('Stopped.'));
      expect(hooks.statuses, isNot(contains(BlueyStatus.error)));
    },
  );

  test(
    'job timer bounds transcription and consumes prior stage budget (#199)',
    () {
      var finished = false;
      late SpyHooks hooks;
      final pending = Completer<void>();
      fakeAsync((time) {
        final (runner, brain, _, _, _, transcriber, spy, _) = _rig(
          jobTimeout: const Duration(seconds: 3),
          now: () => time.getClock(DateTime.utc(2026, 10, 10)).now(),
          deleteRecording: (_) async {},
        );
        hooks = spy;
        transcriber.onTranscribe = () => pending.future;
        unawaited(
          runner.process(file).then((_) {
            finished = true;
          }),
        );
        time.flushMicrotasks();
        time.elapse(const Duration(seconds: 3));
        time.flushMicrotasks();
        expect(brain.lastAsked, isNull);
        expect(hooks.statuses, contains(BlueyStatus.error));
        expect(
          hooks.bubbles.any(
            (b) => b?.startsWith('Transcription failed') ?? false,
          ),
          isTrue,
        );
        pending.complete();
        time.flushMicrotasks();
      });
      expect(finished, isTrue);
    },
  );

  test(
    'brain timeout discards late stream/reply and uses remaining budget',
    () {
      var finished = false;
      late SpyHooks hooks;
      late FakeBrain brain;
      fakeAsync((time) {
        final origin = DateTime.utc(2026, 10, 10);
        var spent = Duration.zero;
        final (runner, b, _, _, speech, _, spy, conversation) = _rig(
          jobTimeout: const Duration(seconds: 3),
          now: () => time.getClock(origin).now().add(spent),
          deleteRecording: (_) async {},
          onSettings: () {
            spent = const Duration(seconds: 2);
          },
        );
        // Deadline starts before the settings/STT stage budget is consumed.
        spent = Duration.zero;
        brain = b;
        hooks = spy;
        brain.asking = Completer<BrainReply>();

        unawaited(
          runner.process(file).then((_) {
            finished = true;
          }),
        );
        time.flushMicrotasks();
        expect(brain.askEntered.isCompleted, isTrue);
        time.elapse(const Duration(milliseconds: 999));
        time.flushMicrotasks();
        expect(hooks.statuses, isNot(contains(BlueyStatus.error)));
        time.elapse(const Duration(milliseconds: 1));
        time.flushMicrotasks();
        brain.stream?.call('late timed stream');
        brain.asking!.complete(const BrainReply(spoken: 'late timed reply'));
        time.flushMicrotasks();
        expect(hooks.says, isEmpty);
        expect(speech.synthesized, 0);
        expect(conversation.where((e) => e.first == 'bluey'), isEmpty);
        expect(hooks.bubbles, isNot(contains('late timed stream')));
        expect(hooks.statuses, contains(BlueyStatus.error));
      });
      expect(finished, isTrue);
    },
  );

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
  for (final resume in [false, true]) {
    void invalidate(FakeGate gate) {
      if (resume) {
        gate.generation++;
      } else {
        gate.killed = true;
      }
    }

    test(
      'entered streaming/plain ask discards late reply after ${resume ? 'kill+resume' : 'Stop'}',
      () async {
        final (runner, brain, gate, _, speech, _, hooks, conversation) = _rig();
        final dir = await Directory.systemTemp.createTemp('runner-stop-');
        addTearDown(() => dir.delete(recursive: true));
        final recording = await File('${dir.path}/audio')
            .writeAsString('fixture');
        brain.asking = Completer<BrainReply>();
        final processing = runner.process(recording);
        await brain.askEntered.future;
        invalidate(gate);
        brain.stream?.call('late stream');
        brain.asking!.complete(const BrainReply(spoken: 'stale answer'));
        await processing;
        brain.stream?.call('later after finished');
        expect(conversation, [
          ['user', 'hello there'],
        ]);
        expect(hooks.bubbles, isNot(contains('late stream')));
        expect(hooks.bubbles, isNot(contains('later after finished')));
        expect(hooks.says, isEmpty);
        expect(speech.synthesized, 0);
        expect(hooks.faces, isNot(contains(Mood.talking)));
        expect(await recording.exists(), isFalse);
      },
    );
    test(
      'entered allowed confirmation never executes after ${resume ? 'kill+resume' : 'Stop'}',
      () async {
        final (runner, brain, gate, exec, _, _, hooks, _) = _rig();
        brain.replies.add(
          BrainReply(spoken: '', toolCall: ToolCall('click', {})),
        );
        gate.pending = Completer<bool>();
        final processing = runner.process(file);
        await gate.entered.future;
        invalidate(gate);
        gate.pending!.complete(true);
        await processing;
        expect(exec.calls, 0);
        expect(brain.toolResults, isEmpty);
        expect(hooks.says, isEmpty);
        expect(hooks.bubbles, contains('Stopped.'));
      },
    );
    for (final denied in [false, true]) {
      test(
        'entered ${denied ? 'denied' : 'executed'} tool result discards late reply after ${resume ? 'kill+resume' : 'Stop'}',
        () async {
          final (runner, brain, gate, exec, speech, _, hooks, conversation) =
              _rig();
          brain.replies.add(
            BrainReply(spoken: '', toolCall: ToolCall('click', {})),
          );
          gate.allow = !denied;
          brain.reacting = Completer<BrainReply>();
          final processing = runner.process(file);
          await brain.resultEntered.future;
          invalidate(gate);
          brain.reacting!.complete(const BrainReply(spoken: 'late result'));
          await processing;
          expect(exec.calls, denied ? 0 : 1);
          expect(conversation.where((e) => e.first == 'bluey'), isEmpty);
          expect(speech.synthesized, 0);
          expect(hooks.says, isEmpty);
        },
      );
    }
    for (final fails in [false, true]) {
      test(
        'entered synthesis ${fails ? 'error' : 'success'} cannot say/play after ${resume ? 'kill+resume' : 'Stop'}',
        () async {
          final (runner, brain, gate, _, speech, _, hooks, _) = _rig();
          brain.replies.add(const BrainReply(spoken: 'active answer'));
          speech.pending = Completer<List<int>>();
          final processing = runner.process(file);
          await speech.entered.future;
          invalidate(gate);
          if (fails) {
            speech.pending!.completeError(SpeechException('late error'));
          } else {
            speech.pending!.complete([1, 2, 3]);
          }
          await processing;
          expect(hooks.says, isEmpty);
          expect(speech.played, isNull);
          expect(
            hooks.bubbles.any((b) => b?.contains('TTS failed') ?? false),
            isFalse,
          );
        },
      );
    }
  }

  for (final delayed in [
    'settings',
    'stt-settings',
    'transcription',
    'ask',
    'confirmation',
    'execution',
    'result',
    'synthesis',
  ]) {
    test(
      'whole-job budget expires at entered $delayed and discards late completion',
      () async {
        var now = DateTime.utc(2026, 10, 10);
        final brain = FakeBrain(),
            gate = FakeGate(),
            exec = FakeExecutor(),
            speech = FakeSpeech();
        final transcriber = FakeTranscriber(), hooks = SpyHooks();
        final entered = Completer<void>(), release = Completer<void>();
        Future<void> delay() async {
          entered.complete();
          await release.future;
          now = now.add(const Duration(seconds: 4));
        }

        if (delayed == 'transcription') transcriber.onTranscribe = delay;
        if (delayed == 'ask') {
          brain.asking = Completer<BrainReply>();
        }
        if (delayed == 'confirmation') gate.pending = Completer<bool>();
        if (delayed == 'execution') exec.pending = Completer<ToolResult>();
        if (delayed == 'result') brain.reacting = Completer<BrainReply>();
        if (delayed == 'synthesis') speech.pending = Completer<List<int>>();
        brain.replies.addAll([
          if (['confirmation', 'execution', 'result'].contains(delayed))
            BrainReply(spoken: '', toolCall: ToolCall('click', {})),
          const BrainReply(spoken: 'active'),
        ]);
        final conversation = <List<String>>[];
        final runner = RequestRunner(
          safety: gate,
          tools: exec,
          speech: speech,
          transcriber: transcriber,
          now: () => now,
          jobTimeout: const Duration(seconds: 3),
          settingsLoader: () async {
            if (delayed == 'settings') await delay();
            now = now.add(const Duration(milliseconds: 500));
            return _settings;
          },
          sttLoader: () async {
            if (delayed == 'stt-settings') await delay();
            now = now.add(const Duration(milliseconds: 500));
            return const SttSettings(baseUrl: 'http://stt.local/v1');
          },
          brainProvider: () => brain,
          matchRoutine: (_) => null,
          hooks: hooks,
          addToConversation: (role, text) => conversation.add([role, text]),
          currentVoice: () => 'alloy',
        );
        final dir = await Directory.systemTemp.createTemp('runner-deadline-');
        addTearDown(() => dir.delete(recursive: true));
        final recording = await File('${dir.path}/audio')
            .writeAsString('fixture');
        final processing = runner.process(recording);
        if (['settings', 'stt-settings', 'transcription'].contains(delayed)) {
          await entered.future;
          release.complete();
        } else {
          switch (delayed) {
            case 'ask':
              await brain.askEntered.future;
              now = now.add(const Duration(seconds: 3));
              brain.asking!.complete(const BrainReply(spoken: 'late'));
            case 'confirmation':
              await gate.entered.future;
              now = now.add(const Duration(seconds: 3));
              gate.pending!.complete(true);
            case 'execution':
              await exec.entered.future;
              now = now.add(const Duration(seconds: 3));
              exec.pending!.complete(const ToolResult('late'));
            case 'result':
              await brain.resultEntered.future;
              now = now.add(const Duration(seconds: 3));
              brain.reacting!.complete(const BrainReply(spoken: 'late'));
            case 'synthesis':
              await speech.entered.future;
              now = now.add(const Duration(seconds: 3));
              speech.pending!.complete([1, 2, 3]);
          }
        }
        await processing;
        expect(hooks.says, isEmpty);
        expect(speech.played, isNull);
        expect(hooks.statuses, contains(BlueyStatus.error));
        expect(await recording.exists(), isFalse);
        if (delayed != 'synthesis') {
          expect(conversation.where((e) => e.first == 'bluey'), isEmpty);
        }
        if (delayed == 'confirmation') expect(exec.calls, 0);
      },
    );
  }
  for (final stage in ['confirmation', 'execution', 'synthesis']) {
    for (final lateError in [false, true]) {
      test(
        'pending $stage times out at remaining budget before late ${lateError ? 'error' : 'success'}',
        () {
          fakeAsync((time) {
            final origin = DateTime.utc(2026, 10, 10);
            var spent = Duration.zero;
            var finished = false, cleaned = false;
            final (runner, brain, gate, exec, speech, _, hooks, _) = _rig(
              jobTimeout: const Duration(seconds: 3),
              now: () => time.getClock(origin).now().add(spent),
              onSettings: () {
                spent = const Duration(seconds: 2);
              },
              deleteRecording: (_) async {
                cleaned = true;
              },
            );
            if (stage == 'confirmation') gate.pending = Completer<bool>();
            if (stage == 'execution') exec.pending = Completer<ToolResult>();
            if (stage == 'synthesis') speech.pending = Completer<List<int>>();
            brain.replies.addAll([
              if (stage != 'synthesis')
                BrainReply(spoken: '', toolCall: ToolCall('click', {})),
              const BrainReply(spoken: 'active answer'),
            ]);
            unawaited(
              runner.process(file).then((_) {
                finished = true;
              }),
            );
            time.flushMicrotasks();
            final entered = switch (stage) {
              'confirmation' => gate.entered.isCompleted,
              'execution' => exec.entered.isCompleted,
              _ => speech.entered.isCompleted,
            };
            expect(entered, isTrue);
            time.elapse(const Duration(milliseconds: 999));
            time.flushMicrotasks();
            expect(finished, isFalse);
            expect(cleaned, isFalse);
            time.elapse(const Duration(milliseconds: 1));
            time.flushMicrotasks();
            expect(finished, isTrue);
            expect(cleaned, isTrue);
            expect(hooks.statuses, contains(BlueyStatus.error));
            expect(hooks.says, isEmpty);
            expect(speech.played, isNull);
            final bubblesBefore = List<String?>.of(hooks.bubbles);
            final facesBefore = List<Mood>.of(hooks.faces);
            if (stage == 'confirmation') {
              if (lateError) {
                gate.pending!.completeError(StateError('late confirmation'));
              } else {
                gate.pending!.complete(true);
              }
            } else if (stage == 'execution') {
              if (lateError) {
                exec.pending!.completeError(StateError('late tool'));
              } else {
                exec.pending!.complete(const ToolResult('late tool'));
              }
            } else {
              if (lateError) {
                speech.pending!.completeError(SpeechException('late speech'));
              } else {
                speech.pending!.complete([1, 2, 3]);
              }
            }
            time.flushMicrotasks();
            expect(hooks.says, isEmpty);
            expect(speech.played, isNull);
            expect(hooks.bubbles, bubblesBefore);
            expect(hooks.faces, facesBefore);
            expect(brain.toolResults, isEmpty);
            if (stage == 'confirmation') expect(exec.calls, 0);
          });
        },
      );
    }
  }
}
