import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../link/models.dart';
import '../llm/llm_provider.dart' show BlueyStatus;
import 'audio_capture.dart';
import 'brain_host.dart';
import 'characters.dart';
import 'conversation.dart';
import 'perf_monitor.dart';
import 'request_interfaces.dart';
import 'routines.dart';
import 'safety_gate.dart';
import 'settings_store.dart';
import 'speech.dart';
import 'tool_executor.dart';
import 'stt.dart';

/// Side effects of the request loop that belong to the UI/server layer.
/// MacHome wires these to setState, receipts and the phone server; tests
/// record them. All hooks are no-ops by default.
class RequestHooks {
  const RequestHooks();

  /// The chat bubble text (null clears it).
  void bubble(String? text) {}

  /// Tray/status indicator changes.
  void status(BlueyStatus status) {}

  /// The companion face changed (local only).
  void face(FaceState face) {}

  /// The face should also be pushed to the paired phone.
  void sendFace(FaceState face) {}

  /// A 'say' packet is ready: receipts tracking + broadcast.
  void say(Packet packet, String spoken) {}
}

/// Transcribe -> ask the brain -> run tools -> speak (#135).
/// Extracted from MacHome so kill/denial/timeout branches are testable
/// without pumping the app (#107, #110).
class RequestRunner {
  RequestRunner({
    TranscriberLike? transcriber,
    this.sttLoader = SttSettings.load,
    GateLike? safety,
    ExecutorLike? tools,
    SpeechLike? speech,
    BrainLike? Function()? brainProvider,
    Future<BrainSettings> Function()? settingsLoader,
    Routine? Function(String utterance)? matchRoutine,
    void Function(String role, String text)? addToConversation,
    String Function()? currentVoice,
    this.hooks = const RequestHooks(),
    this.stepTimeout = const Duration(seconds: 60),
    this.jobTimeout = const Duration(minutes: 3),
    this.maxToolSteps = 5,
    this.maxQueued = 2,
    DateTime Function()? now,
    Future<void> Function(File)? deleteRecording,
  }) : _deleteRecording = deleteRecording ?? AudioCapture.deleteQuietly,
       _now = now ?? DateTime.now,
       _injectedTranscriber = transcriber,
       safety = safety ?? SafetyGate(),
       tools = tools ?? ToolExecutor(),
       speech = speech ?? SpeechService(),
       brainProvider = brainProvider ?? (() => BrainHost.brain.value),
       settingsLoader = settingsLoader ?? SettingsStore.load,
       matchRoutine = matchRoutine ?? RoutineStore.instance.match,
       addToConversation = addToConversation ?? ConversationStore.instance.add,
       currentVoice =
           currentVoice ?? (() => CharacterStore.instance.current.value.voice);

  final DateTime Function() _now;
  final Future<void> Function(File) _deleteRecording;

  /// Set when the caller injected a transcriber (tests, or a host that owns
  /// its own provider). Left null in the app, where the provider is resolved
  /// per request from the saved STT settings so switching provider in
  /// Settings actually takes effect (#196).
  final TranscriberLike? _injectedTranscriber;

  /// The provider for [sttSettings]: the injected one when present,
  /// otherwise the concrete provider its kind names.
  TranscriberLike transcriberFor(SttSettings sttSettings) =>
      _injectedTranscriber ?? SttProviders.create(sttSettings);

  /// Where STT configuration comes from (#196); tests inject a fake.
  final Future<SttSettings> Function() sttLoader;

  /// The safety gate consulted before every tool run.
  final GateLike safety;

  /// Executes the tool calls the brain returns.
  final ExecutorLike tools;

  /// Speaks the replies.
  final SpeechLike speech;

  /// Lazily supplies the current brain (null = not configured).
  final BrainLike? Function() brainProvider;

  /// Loads current brain settings per request.
  final Future<BrainSettings> Function() settingsLoader;

  /// Matches an utterance against stored routines before the brain sees it.
  final Routine? Function(String utterance) matchRoutine;

  /// Appends a turn to the conversation log.
  final void Function(String role, String text) addToConversation;

  /// The currently selected TTS voice id.
  final String Function() currentVoice;

  /// Lifecycle callbacks (listening, thinking, speaking, ...).
  final RequestHooks hooks;

  /// Per-step ceiling (one transcribe/brain/speak call).
  final Duration stepTimeout;

  /// Tool-call loop ceiling for one request.
  final int maxToolSteps;

  /// Wall-clock deadline for the whole transcribe -> brain -> speak job
  /// (#199): a slow transcriber cannot hold the pipeline open past this,
  /// whatever the per-step timeouts allow.
  final Duration jobTimeout;

  /// How many utterances may wait behind the active run (#366). A request
  /// beyond this is rejected with a bubble and its recording deleted.
  final int maxQueued;

  /// Whether the companion is awake; decides the face reset after a run.
  bool awake = true;

  bool _busy = false;
  final _waiting = <_Waiting>[];

  /// Utterances currently queued behind the active run.
  int get queuedCount => _waiting.length;

  /// Process one recorded utterance. Deletes the recording when finished -
  /// voice files must not pile up in temp storage (#116).
  ///
  /// One run at a time (#366): overlapping utterances from the Mac mic, the
  /// hold key and the phone queue behind the active run (up to [maxQueued]);
  /// further ones are rejected. A Stop (kill or generation bump) discards
  /// everything that was queued before it instead of running it late.
  Future<void> process(File file) async {
    // Admission generation: a Stop/resume after this point revokes the
    // request even if its turn is granted later.
    final admitted = safety.generation;
    if (_busy) {
      if (_waiting.length >= maxQueued) {
        hooks.bubble('Busy - try again in a moment.');
        await _deleteRecording(file);
        return;
      }
      final waiting = _Waiting(admitted);
      _waiting.add(waiting);
      if (!await waiting.turn.future) {
        hooks.bubble('Stopped.');
        await _deleteRecording(file);
        return;
      }
    } else {
      _busy = true;
    }
    try {
      await _run(file, admitted);
    } finally {
      _handOff();
      // With another utterance starting, leave the shared face/status to it
      // instead of reporting idle during live work.
      if (!_busy) {
        final face = FaceState(mood: awake ? Mood.listening : Mood.sleepy);
        hooks
          ..face(face)
          ..status(BlueyStatus.listening)
          ..sendFace(face);
      }
    }
  }

  /// Starts the next still-valid queued utterance, dropping stopped ones.
  void _handOff() {
    while (_waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      if (safety.killed || safety.generation != next.generation) {
        next.turn.complete(false);
        continue;
      }
      next.turn.complete(true); // _busy stays true for the next run
      return;
    }
    _busy = false;
  }

  Future<void> _run(File file, int admitted) async {
    hooks
      ..face(FaceState(mood: Mood.thinking))
      ..status(BlueyStatus.thinking);
    // #199: snapshot the generation BEFORE transcription starts and bound
    // the whole job. A Stop mid-transcription must discard the late
    // transcript instead of submitting it to the brain.
    final runGeneration = admitted;
    bool cancelled() => safety.killed || safety.generation != runGeneration;
    final deadline = _now().add(jobTimeout);
    var finished = false;
    Duration remaining() {
      final r = deadline.difference(_now());
      return r.isNegative ? Duration.zero : r;
    }

    void check() {
      if (cancelled()) throw const _RunStopped();
      if (remaining() == Duration.zero) {
        throw TimeoutException('Request exceeded whole-job deadline');
      }
    }

    // Timeouts discard results, not underlying native/network work. Every
    // stage checks generation and the same deadline on both sides of await.
    Future<T> stage<T>(
      Future<T> Function() operation, {
      bool stt = false,
    }) async {
      check();
      final budget = remaining() < stepTimeout ? remaining() : stepTimeout;
      try {
        final value = await operation().timeout(budget);
        check();
        return value;
      } on TimeoutException {
        if (cancelled()) throw const _RunStopped();
        if (stt) {
          throw SttException(
            SttErrorKind.timeout,
            'Transcription exceeded request time budget',
          );
        }
        rethrow;
      } catch (_) {
        check();
        rethrow;
      }
    }

    try {
      final settings = await stage(settingsLoader);
      final sttSettings = await stage(sttLoader);
      final text = await stage(
        () => PerfMonitor.instance.measure(
          'listening.transcription',
          () => transcriberFor(sttSettings).transcribe(file, sttSettings),
        ),
        stt: true,
      );

      if (text.isEmpty) {
        hooks.bubble("Didn't catch that.");
        return;
      }
      check();
      hooks.bubble(text);
      addToConversation('user', text);
      // A routine trigger expands into its standing instructions (#56).
      final routine = matchRoutine(text);
      final effectiveText = routine == null
          ? text
          : '$text\n\n[Routine "${routine.name}"] ${routine.instructions}';
      final brain = brainProvider();
      if (brain == null) {
        hooks.bubble('Set up the brain in settings first.');
        return;
      }
      var reply = await stage(
        () => PerfMonitor.instance.measure(
          'thinking.brain',
          () => brain.askStreaming(
            effectiveText,
            onToken: (token) {
              if (!finished && !cancelled() && remaining() > Duration.zero) {
                hooks.bubble(token);
              }
            },
          ),
        ),
      );
      // Tool loop: let the brain act, then react to what happened.
      // #107/#199: a kill (or kill+resume, which bumps the generation) stops
      // this run at every await boundary, transcription included.
      var steps = 0;
      while (reply.toolCall != null && steps < maxToolSteps) {
        if (cancelled()) {
          hooks.bubble('Stopped.');
          return;
        }
        steps++;
        final call = reply.toolCall!;
        final allowed = await stage(
          () => safety.authorize(call.name, call.arguments),
        );
        if (!allowed) {
          reply = await stage(
            () => brain.toolResult(call.name, 'Denied by the user.'),
          );
          continue;
        }
        check();
        hooks.status(BlueyStatus.acting);
        final result = await stage(
          () => PerfMonitor.instance.measure(
            'acting.tool.${call.name}',
            () => tools.execute(call),
          ),
        );
        reply = await stage(
          () => brain.toolResult(
            call.name,
            result.text,
            images: [if (result.imageBase64 != null) result.imageBase64!],
          ),
        );
      }
      check();
      if (reply.toolCall != null) {
        hooks.bubble('Too many steps - stopping here.');
      }
      if (reply.spoken.isNotEmpty) {
        addToConversation('bluey', reply.spoken);
        final talking = FaceState(mood: Mood.talking);
        hooks
          ..bubble(reply.spoken)
          ..face(talking)
          ..sendFace(talking);
        try {
          final voiced = BrainSettings(
            backend: settings.backend,
            baseUrl: settings.baseUrl,
            model: settings.model,
            apiKey: settings.apiKey,
            transcriptionBaseUrl: settings.transcriptionBaseUrl,
            transcriptionModel: settings.transcriptionModel,
            ttsBaseUrl: settings.ttsBaseUrl,
            ttsModel: settings.ttsModel,
            ttsVoice: currentVoice(),
          );
          final audio = await stage(
            () => speech.synthesize(reply.spoken, voiced),
          );
          check();
          hooks.say(
            Packet(
              command: 'say',
              text: reply.spoken,
              audio: base64Encode(audio),
            ),
            reply.spoken,
          );
          unawaited(speech.playBytes(audio));
        } on SpeechException catch (e) {
          check();
          hooks
            ..say(Packet(command: 'say', text: reply.spoken), reply.spoken)
            ..bubble('${reply.spoken}\n(TTS failed: $e)');
        }
      }
    } on _RunStopped {
      hooks.bubble('Stopped.');
    } on SttException catch (e) {
      hooks
        ..bubble('Transcription failed: $e')
        ..status(BlueyStatus.error);
    } catch (e) {
      hooks
        ..bubble('Error: $e')
        ..status(BlueyStatus.error);
    } finally {
      finished = true;
      await _deleteRecording(file); // #116
    }
  }
}

class _RunStopped implements Exception {
  const _RunStopped();
}

class _Waiting {
  _Waiting(this.generation);
  final int generation;
  final turn = Completer<bool>();
}
