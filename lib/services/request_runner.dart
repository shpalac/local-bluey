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
  }) : _injectedTranscriber = transcriber,
       safety = safety ?? SafetyGate(),
       tools = tools ?? ToolExecutor(),
       speech = speech ?? SpeechService(),
       brainProvider = brainProvider ?? (() => BrainHost.brain.value),
       settingsLoader = settingsLoader ?? SettingsStore.load,
       matchRoutine = matchRoutine ?? RoutineStore.instance.match,
       addToConversation = addToConversation ?? ConversationStore.instance.add,
       currentVoice =
           currentVoice ?? (() => CharacterStore.instance.current.value.voice);

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
  final GateLike safety;
  final ExecutorLike tools;
  final SpeechLike speech;
  final BrainLike? Function() brainProvider;
  final Future<BrainSettings> Function() settingsLoader;
  final Routine? Function(String utterance) matchRoutine;
  final void Function(String role, String text) addToConversation;
  final String Function() currentVoice;
  final RequestHooks hooks;
  final Duration stepTimeout;
  final int maxToolSteps;

  /// Wall-clock deadline for the whole transcribe -> brain -> speak job
  /// (#199): a slow transcriber cannot hold the pipeline open past this,
  /// whatever the per-step timeouts allow.
  final Duration jobTimeout;

  /// Whether the companion is awake; decides the face reset after a run.
  bool awake = true;

  /// Process one recorded utterance. Deletes the recording when finished -
  /// voice files must not pile up in temp storage (#116).
  Future<void> process(File file) async {
    hooks
      ..face(FaceState(mood: Mood.thinking))
      ..status(BlueyStatus.thinking);
    // #199: snapshot the generation BEFORE transcription starts and bound
    // the whole job. A Stop mid-transcription must discard the late
    // transcript instead of submitting it to the brain.
    final runGeneration = safety.generation;
    bool cancelled() => safety.killed || safety.generation != runGeneration;
    final deadline = DateTime.now().add(jobTimeout);
    Duration remaining() {
      final r = deadline.difference(DateTime.now());
      return r.isNegative ? Duration.zero : r;
    }

    try {
      final settings = await settingsLoader();
      final sttSettings = await sttLoader();
      final text = await PerfMonitor.instance.measure(
        'listening.transcription',
        () => transcriberFor(sttSettings)
            .transcribe(file, sttSettings)
            .timeout(
              remaining(),
              onTimeout: () => throw SttException(
                SttErrorKind.timeout,
                'Transcription exceeded the ${jobTimeout.inSeconds}s job deadline',
              ),
            ),
      );

      if (cancelled()) {
        hooks.bubble('Stopped.');
        return;
      }
      if (text.isEmpty) {
        hooks.bubble("Didn't catch that.");
        return;
      }
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
      var reply = await PerfMonitor.instance.measure(
        'thinking.brain',
        () => brain
            .askStreaming(effectiveText, onToken: hooks.bubble)
            .timeout(stepTimeout),
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
        if (!await safety.authorize(call.name, call.arguments)) {
          if (cancelled()) {
            hooks.bubble('Stopped.');
            return;
          }
          reply = await brain
              .toolResult(call.name, 'Denied by the user.')
              .timeout(stepTimeout);
          continue;
        }
        hooks.status(BlueyStatus.acting);
        final result = await PerfMonitor.instance.measure(
          'acting.tool.${call.name}',
          () => tools.execute(call),
        );
        if (cancelled()) {
          hooks.bubble('Stopped.');
          return;
        }
        reply = await brain
            .toolResult(
              call.name,
              result.text,
              images: [if (result.imageBase64 != null) result.imageBase64!],
            )
            .timeout(stepTimeout);
      }
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
          final audio = await speech.synthesize(reply.spoken, voiced);
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
          hooks
            ..say(Packet(command: 'say', text: reply.spoken), reply.spoken)
            ..bubble('${reply.spoken}\n(TTS failed: $e)');
        }
      }
    } on SttException catch (e) {
      hooks
        ..bubble('Transcription failed: $e')
        ..status(BlueyStatus.error);
    } catch (e) {
      hooks
        ..bubble('Error: $e')
        ..status(BlueyStatus.error);
    } finally {
      await AudioCapture.deleteQuietly(file); // #116
      final face = FaceState(mood: awake ? Mood.listening : Mood.sleepy);
      hooks
        ..face(face)
        ..status(BlueyStatus.listening)
        ..sendFace(face);
    }
  }
}
