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
import 'transcription.dart';

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
    this.maxToolSteps = 5,
  }) : transcriber = transcriber ?? TranscriptionService(),
       safety = safety ?? SafetyGate(),
       tools = tools ?? ToolExecutor(),
       speech = speech ?? SpeechService(),
       brainProvider = brainProvider ?? (() => BrainHost.brain.value),
       settingsLoader = settingsLoader ?? SettingsStore.load,
       matchRoutine = matchRoutine ?? RoutineStore.instance.match,
       addToConversation = addToConversation ?? ConversationStore.instance.add,
       currentVoice =
           currentVoice ?? (() => CharacterStore.instance.current.value.voice);

  final TranscriberLike transcriber;
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

  /// Whether the companion is awake; decides the face reset after a run.
  bool awake = true;

  /// Process one recorded utterance. Deletes the recording when finished -
  /// voice files must not pile up in temp storage (#116).
  Future<void> process(File file) async {
    hooks
      ..face(FaceState(mood: Mood.thinking))
      ..status(BlueyStatus.thinking);
    try {
      final settings = await settingsLoader();
      final text = await PerfMonitor.instance.measure(
        'listening.transcription',
        () => transcriber.transcribe(file, settings),
      );

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
      // #107: a kill (or kill+resume, which bumps the generation) stops this
      // run at every await boundary, not only at the top of the loop.
      final runGeneration = safety.generation;
      bool cancelled() => safety.killed || safety.generation != runGeneration;
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
    } on TranscriptionException catch (e) {
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
