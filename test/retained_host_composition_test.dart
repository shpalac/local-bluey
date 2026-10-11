import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_bluey/services/perf_monitor.dart';
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/llm/brain.dart';
import 'package:local_bluey/llm/ollama_provider.dart';
import 'package:local_bluey/llm/openai_compatible_provider.dart';
import 'package:local_bluey/services/brain_host.dart';
import 'package:local_bluey/services/host_reload_controller.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/request_interfaces.dart';
import 'package:local_bluey/services/request_runner.dart';
import 'package:local_bluey/services/safety_gate.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/native_control.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/services/stt.dart';
import 'package:local_bluey/services/watch_vision.dart';

const oldUrl = 'https://retained.invalid/v1';
const newUrl = 'https://replacement.invalid/v1';
const freshUrl = 'https://fresh-settings.invalid/v1';
BrainSettings config(String url) => BrainSettings(
  backend: BrainBackend.openAiCompatible,
  baseUrl: url,
  model: 'synthetic-model',
);

/// Never delegates to an IO client. Every unexpected endpoint fails locally.
class InterceptedClient extends http.BaseClient {
  final requests = <({String method, Uri url, Map<String, dynamic> body})>[];
  final entered = Completer<void>();
  Completer<void>? hold;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) throw StateError('client closed');
    if (request.method != 'POST' ||
        !{
          'retained.invalid',
          'replacement.invalid',
        }.contains(request.url.host) ||
        !{'/v1/chat/completions', '/v1/api/chat'}.contains(request.url.path)) {
      throw StateError('network forbidden: unexpected fixture endpoint');
    }
    final body = jsonDecode(
      utf8.decode(await request.finalize().toBytes()),
    ) as Map<String, dynamic>;
    requests.add((method: request.method, url: request.url, body: body));
    if (!entered.isCompleted) entered.complete();
    await hold?.future;
    final openAi = request.url.path.endsWith('completions');
    final streaming = body['stream'] == true;
    final response = streaming
        ? openAi
              ? 'data: {"choices":[{"delta":{"content":"fixture answer"}}]}\n\n'
              : '{"message":{"content":"fixture answer"},"done":true}\n'
        : openAi
        ? '{"choices":[{"message":{"content":"fixture answer"}}]}'
        : '{"message":{"content":"fixture answer"}}';
    return http.StreamedResponse(Stream.value(utf8.encode(response)), 200);
  }

  void release() {
    if (hold != null && !hold!.isCompleted) hold!.complete();
  }

  @override
  void close() => closed = true;
}

class Transcript extends TranscriberLike {
  final entered = Completer<void>();
  Completer<void>? hold;
  int calls = 0;
  @override
  Future<String> transcribe(File audio, SttSettings settings) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    await hold?.future;
    return 'synthetic question';
  }

  void release() {
    if (hold != null && !hold!.isCompleted) hold!.complete();
  }
}

/// TTS is a distinct, deliberately intercepted dependency, not part of proof.
class SilentSpeech extends SpeechLike {
  final settings = <BrainSettings>[];
  @override
  Future<List<int>> synthesize(String text, BrainSettings value) async {
    settings.add(value);
    return [1];
  }

  @override
  Future<void> playBytes(List<int> bytes) async {}
}

class Fixture {
  Fixture(this.ollama) {
    previousPrivacy = PrivacyGuard.debugPreferences;
    previousOverride = PrivacyGuard.debugLocalOnlyOverride;
    privacy = LocalOnlyPreferences(
      read: () async {
        reads++;
        if (readFails) throw StateError('synthetic read failure');
        return local;
      },
      write: (value) async {
        local = value;
        return true;
      },
      remove: () async {
        local = null;
        return true;
      },
    );
    PrivacyGuard.debugPreferences = privacy;
    PrivacyGuard.debugLocalOnlyOverride = null;
    host = BrainHostState(
      load: () async {
        if (failure == 'load') throw StateError('synthetic load failure');
        return config(selectedUrl);
      },
      refusal: (settings) async {
        if (failure == 'refusal') throw StateError('synthetic refusal failure');
        return PrivacyGuard.refusal(settings);
      },
      build: (settings) => Brain(
        provider: ollama
            ? OllamaProvider(
                baseUrl: settings.baseUrl,
                model: settings.model,
                client: client,
              )
            : OpenAiCompatibleProvider(
                baseUrl: settings.baseUrl,
                model: settings.model,
                client: client,
              ),
      ),
    );
    controller = HostReloadController(reload: host.reload);
    addTearDown(dispose);
  }

  final bool ollama;
  final client = InterceptedClient();
  final transcript = Transcript();
  final speech = SilentSpeech();
  final gate = SafetyGate();
  final pending = <Future<void>>[];
  final watches = <ScreenWatch>[];
  final captures = <Completer<Uint8List>>[];
  late final BrainHostState host;
  late final HostReloadController controller;
  late final LocalOnlyPreferences privacy;
  late final LocalOnlyPreferences? previousPrivacy;
  late final bool? previousOverride;
  bool? local = false;
  bool readFails = false;
  int reads = 0, deleted = 0;
  String? failure;
  String selectedUrl = oldUrl;
  Directory? directory;
  File? file;

  String endpoint(String url) =>
      '$url/${ollama ? 'api/chat' : 'chat/completions'}';

  Future<Brain> retained(String failStage) async {
    await controller.reload();
    final brain = host.brain.value!;
    await privacy.set(true);
    selectedUrl = newUrl;
    failure = failStage;
    await controller.reload();
    expect(controller.failed, true);
    expect(controller.loading, false);
    expect(host.brain.value, same(brain));
    expect(host.refusedReason.value, isNull);
    expect(host.remoteActive.value, true);
    expect(privacy.value, true);
    return brain;
  }

  Future<void> replace() async {
    failure = null;
    await privacy.set(false);
    selectedUrl = newUrl;
    await controller.reload();
    expect(controller.failed, false);
  }

  Future<File> recording() async {
    directory ??= await Directory.systemTemp.createTemp('retained-host-459-');
    file ??= File('${directory!.path}/synthetic.m4a');
    await file!.writeAsBytes([1, 2]);
    return file!;
  }

  RequestRunner runner({bool settingsFail = false}) => RequestRunner(
    transcriber: transcript,
    safety: gate,
    speech: speech,
    brainProvider: () => host.brain.value,
    settingsLoader: () async {
      if (settingsFail) throw StateError('synthetic fresh settings failure');
      return config(freshUrl);
    },
    sttLoader: () async => const SttSettings(baseUrl: 'https://stt.invalid'),
    matchRoutine: (_) => null,
    addToConversation: (_, _) {},
    currentVoice: () => 'synthetic',
    deleteRecording: (recording) async {
      expect(recording.path, file!.path);
      if (await recording.exists()) await recording.delete();
      deleted++;
    },
  );

  Future<void> request({bool settingsFail = false}) async {
    final operation = runner(settingsFail: settingsFail)
        .process(await recording());
    pending.add(operation);
    await operation;
  }

  Future<ScreenWatch> watch() async {
    final watch = ScreenWatch.forTesting(
      allowlist: () async => ['Editor'],
      denylist: () async => [],
    );
    watches.add(watch);
    expect(await watch.start(consentConfirmed: true), isNull);
    return watch;
  }

  WatchVision vision(
    ScreenWatch watch, {
    Future<Uint8List> Function()? snapshot,
  }) => WatchVision(
    provider: () => host.brain.value?.provider,
    foreground: () async =>
        (app: 'Editor', title: 'Workspace', locked: false),
    snapshot: () async => ScreenSnapshot(
      jpeg: snapshot == null ? Uint8List.fromList([1, 2]) : await snapshot(),
      targets: 'Workspace tasks',
      width: 320,
      height: 240,
      cropTextVerified: true,
      frontApp: 'Editor',
    ),
    watch: watch,
  );

  Future<T> track<T>(Future<T> operation) {
    pending.add(
      operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return operation;
  }

  Future<void> dispose() async {
    transcript.release();
    client.release();
    for (final capture in captures) {
      if (!capture.isCompleted) capture.complete(Uint8List.fromList([1, 2]));
    }
    await Future.wait(pending);
    for (final watch in watches) {
      watch.dispose();
    }
    controller.dispose();
    host.brain.dispose();
    host.refusedReason.dispose();
    host.remoteActive.dispose();
    PrivacyGuard.debugPreferences = previousPrivacy;
    PrivacyGuard.debugLocalOnlyOverride = previousOverride;
    privacy.dispose();
    client.close();
    if (file != null && await file!.exists()) await file!.delete();
    if (directory != null && await directory!.exists()) {
      await directory!.delete();
    }
    expect(client.closed, true);
    if (directory != null) expect(await directory!.exists(), false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory telemetry;
  setUp(() async {
    telemetry = await Directory.systemTemp.createTemp(
      'retained-459-telemetry-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => telemetry.path);
    SharedPreferences.setMockInitialValues({});
    await PerfMonitor.instance.clear();
    await EgressMonitor.instance.clear();
  });
  tearDown(() async {
    // Drain actual singleton queues before removing their exact fixture files.
    await PerfMonitor.instance.flush();
    await EgressMonitor.instance.load();
    await PerfMonitor.instance.clear();
    await EgressMonitor.instance.clear();
    expect(await telemetry.list().toList(), isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    SharedPreferences.setMockInitialValues({});
    await telemetry.delete();
    expect(await telemetry.exists(), false);
  });
  for (final ollama in [false, true]) {
    final backend = ollama ? 'Ollama' : 'OpenAI';
    for (final stage in ['load', 'refusal']) {
      test(
        '$backend retained $stage failure: fresh settings do not rebuild brain',
        () async {
          final f = Fixture(ollama);
          final retained = await f.retained(stage);
          final reads = f.reads;
          await f.request();
          expect(f.host.brain.value, same(retained));
          expect(f.client.requests, hasLength(1));
          final request = f.client.requests.single;
          expect(request.method, 'POST');
          expect(request.url.toString(), f.endpoint(oldUrl));
          expect(request.body['stream'], true);
          expect(f.speech.settings.single.baseUrl, freshUrl);
          expect(
            f.reads,
            reads,
          ); // No brain transport privacy read was introduced.
          expect(f.deleted, 1);
          expect(await f.file!.exists(), false);
        },
      );
    }
    test(
      '$backend failed fresh request settings prevent transport entry',
      () async {
        final f = Fixture(ollama);
        await f.retained('load');
        await f.request(settingsFail: true);
        expect(f.client.requests, isEmpty);
        expect(f.transcript.calls, 0);
        expect(f.speech.settings, isEmpty);
        expect(f.deleted, 1);
      },
    );
    test(
      '$backend host replacement during transcription changes lazy selection',
      () async {
        final f = Fixture(ollama);
        final old = await f.retained('load');
        f.transcript.hold = Completer<void>();
        final work = f.track(f.request());
        await f.transcript.entered.future;
        await f.replace();
        expect(f.host.brain.value, isNot(same(old)));
        expect(f.client.requests, isEmpty);
        f.transcript.release();
        await work;
        expect(f.client.requests.single.url.toString(), f.endpoint(newUrl));
      },
    );
    test(
      '$backend replacement after stream entry keeps entered object',
      () async {
        final f = Fixture(ollama);
        await f.retained('refusal');
        f.client.hold = Completer<void>();
        final work = f.track(f.request());
        await f.client.entered.future;
        await f.replace();
        f.client.release();
        await work;
        expect(f.client.requests.single.url.toString(), f.endpoint(oldUrl));
        await f.request();
        expect(f.client.requests.map((r) => r.url.toString()), [
          f.endpoint(oldUrl),
          f.endpoint(newUrl),
        ]);
      },
    );
    test(
      '$backend actual retained Brain.toolResult uses nonstream endpoint',
      () async {
        final f = Fixture(ollama);
        final brain = await f.retained('refusal');
        final reads = f.reads;
        final reply = await f.track(
          brain.toolResult('synthetic-readonly', 'fixture result'),
        );
        expect(reply.spoken, 'fixture answer');
        expect(f.client.requests, hasLength(1));
        final request = f.client.requests.single;
        expect(request.url.toString(), f.endpoint(oldUrl));
        expect(request.method, 'POST');
        expect(request.body['stream'], isNot(true));
        expect((request.body['messages'] as List).last['role'], 'tool');
        expect(f.reads, reads);
      },
    );
    test(
      '$backend watch ON gates use retained remote provider, no Brain history',
      () async {
        final f = Fixture(ollama);
        final brain = await f.retained('load');
        final before = brain.history.map((m) => m.toJson()).toList();
        final watch = await f.watch();
        final result = await f.track(f.vision(watch).describe('Editor', 'Workspace'));
        expect(result, 'fixture answer');
        expect(f.privacy.value, true);
        expect(f.client.requests.single.url.toString(), f.endpoint(oldUrl));
        expect(f.client.requests.single.body['stream'], isNot(true));
        expect(f.client.requests.single.body['messages'], hasLength(1));
        expect(brain.history.map((m) => m.toJson()).toList(), before);
      },
    );
    test(
      '$backend watch held capture keeps selected provider; next op resolves replacement',
      () async {
        final f = Fixture(ollama);
        await f.retained('load');
        final watch = await f.watch();
        final entered = Completer<void>(), capture = Completer<Uint8List>();
        f.captures.add(capture);
        final vision = f.vision(
          watch,
          snapshot: () {
            entered.complete();
            return capture.future;
          },
        );
        final work = f.track(vision.describe('Editor', 'Workspace'));
        await entered.future;
        await f.replace();
        await f.privacy.set(
          true,
        ); // Same active session, current bool verified ON.
        expect(f.client.requests, isEmpty);
        capture.complete(Uint8List.fromList([1, 2]));
        expect(await work, 'fixture answer');
        expect(
          await f.track(f.vision(watch).describe('Editor', 'Workspace')),
          'fixture answer',
        );
        expect(f.client.requests.map((r) => r.url.toString()), [
          f.endpoint(oldUrl),
          f.endpoint(newUrl),
        ]);
      },
    );
  }
  test(
    'actual privacy uncertainty refuses watch start and current operation',
    () async {
      final f = Fixture(false);
      await f.retained('load');
      final watch = await f.watch();
      f.readFails = true;
      expect(await f.track(f.vision(watch).describe('Editor', 'Workspace')), isNull);
      expect(watch.isActive, false);
      expect(f.privacy.value, isNull);
      expect(f.client.requests, isEmpty);
      await expectLater(
        watch.start(consentConfirmed: true),
        throwsA(isA<PrivacyStorageException>()),
      );
      expect(watch.isActive, false);
      f.readFails = false;
      expect(await watch.start(consentConfirmed: true), isNull);
      expect(
        await f.track(f.vision(watch).describe('Editor', 'Workspace')),
        'fixture answer',
      );
      expect(f.client.requests, hasLength(1));
    },
  );
  for (final uncertain in [false, true]) {
    test(
      'watch second gate refuses after held capture uncertainty=$uncertain',
      () async {
        final f = Fixture(false);
        await f.retained('refusal');
        final watch = await f.watch();
        final entered = Completer<void>(), capture = Completer<Uint8List>();
        f.captures.add(capture);
        final work = f.track(
          f
              .vision(
                watch,
                snapshot: () {
                  entered.complete();
                  return capture.future;
                },
              )
              .describe('Editor', 'Workspace'),
        );
        await entered.future;
        if (uncertain) {
          f.readFails = true;
        } else {
          await f.privacy.set(false);
        }
        capture.complete(Uint8List.fromList([1, 2]));
        expect(await work, isNull);
        expect(f.client.requests, isEmpty);
        expect(watch.isActive, false);
      },
    );
  }
  test(
    'null retained provider and declined/false-local session do not capture',
    () async {
      final f = Fixture(false);
      await f.privacy.set(true);
      await f.controller.reload(); // Successful remote refusal, null Brain.
      expect(f.host.brain.value, isNull);
      expect(f.host.refusedReason.value, isNotNull);
      final watch = await f.watch();
      var captures = 0;
      final result = await f.track(
        f
            .vision(
              watch,
              snapshot: () async {
                captures++;
                return Uint8List(2);
              },
            )
            .describe('Editor', 'Workspace'),
      );
      expect(result, isNull);
      expect(captures, 0);
      expect(f.client.requests, isEmpty);
      watch.stop();
      expect(await watch.start(consentConfirmed: false), isNotNull);
      await f.privacy.set(false);
      expect(await watch.start(consentConfirmed: true), isNotNull);
      expect(watch.isActive, false);
    },
  );
  test('stop/restart fences entered intercepted watch response, not transport entry', () async {
    final f = Fixture(false);
    await f.retained('load');
    final watch = await f.watch();
    f.client.hold = Completer<void>();
    final vision = f.vision(watch);
    final work = f.track(vision.describe('Editor', 'Workspace'));
    await f.client.entered.future;
    watch.stop();
    expect(await watch.start(consentConfirmed: true), isNull);
    f.client.release();
    expect(await work, isNull);
    expect(await f.track(vision.describe('Editor', 'Workspace')), isNull);
    expect(f.client.requests, hasLength(1));
    expect(
      await f.track(f.vision(watch).describe('Editor', 'Workspace')),
      'fixture answer',
    );
    expect(f.client.requests, hasLength(2));
  });
}
