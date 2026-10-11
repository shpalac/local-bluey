import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/services/diagnostics.dart';
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:local_bluey/services/endpoint_assistant.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const remote = 'https://endpoint-fixture.invalid/v1';

/// No IO client/fallback. Empty GET bodies do not prove zero network bytes.
class CheckClient extends http.BaseClient {
  CheckClient(
    this.url, {
    this.diagnostics = false,
    this.ollama = false,
    this.status = 200,
    this.malformed = false,
  });
  final String url;
  final bool diagnostics, ollama, malformed;
  final int status;
  bool fail = false, closed = false;
  int requests = 0;
  final entered = Completer<void>(), gate = Completer<void>();
  final cancelled = Completer<void>();
  StreamController<List<int>>? body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed || request.method != 'GET' || request.url.toString() != url) {
      throw StateError('network forbidden: unexpected fixture request');
    }
    expect(await request.finalize().toBytes(), isEmpty);
    expect(request.headers.containsKey('authorization'), false);
    if (diagnostics) expect(request.followRedirects, false);
    requests++;
    entered.complete();
    await gate.future;
    if (fail) throw StateError('synthetic transport failure');
    if (diagnostics) {
      body = StreamController<List<int>>(
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
      return http.StreamedResponse(body!.stream, status);
    }
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          malformed
              ? '{'
              : ollama
              ? '{"models":[{"name":"fixture-model"}]}'
              : '{"data":[{"id":"fixture-model"}]}',
        ),
      ),
      status,
    );
  }

  void release() {
    if (!gate.isCompleted) gate.complete();
  }

  Future<void> cleanup() async {
    if (body != null) {
      await cancelled.future;
      await body!.close();
    }
    close();
  }

  @override
  void close() => closed = true;
}

Future<void> assertRows(
  int count, {
  String host = 'endpoint-fixture.invalid',
}) async {
  await EgressMonitor.instance.load(); // Ordered queue barrier, never a sleep.
  expect(EgressMonitor.instance.historyAvailable, true);
  expect(EgressMonitor.instance.entries, hasLength(count));
  if (count == 1) {
    final row = EgressMonitor.instance.entries.single;
    expect(row.host, host);
    expect(row.kind, 'endpoint-check');
    expect(
      row.bytes,
      0,
    ); // Caller amount, not actual packet/HTTP/response size.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory telemetry;
  late bool? previousPrivacy;
  setUp(() async {
    telemetry = await Directory.systemTemp.createTemp('endpoint-egress-488-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => telemetry.path);
    SharedPreferences.setMockInitialValues({});
    previousPrivacy = PrivacyGuard.debugLocalOnlyOverride;
    PrivacyGuard.debugLocalOnlyOverride = true;
    await EgressMonitor.instance.clear();
  });
  tearDown(() async {
    await EgressMonitor.instance.load();
    await EgressMonitor.instance.clear();
    expect(await telemetry.list().toList(), isEmpty);
    PrivacyGuard.debugLocalOnlyOverride = previousPrivacy;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    await telemetry.delete();
    expect(await telemetry.exists(), false);
  });

  for (final ollama in [false, true]) {
    for (final result in ['success', 'throw', 'status', 'json']) {
      test(
        'assistant ${ollama ? "Ollama" : "OpenAI"} $result under local-only records before held GET',
        () async {
          final client = CheckClient(
            '$remote/${ollama ? 'api/tags' : 'models'}',
            ollama: ollama,
            status: result == 'status' ? 400 : 200,
            malformed: result == 'json',
          )..fail = result == 'throw';
          final work = EndpointAssistant(client: client).checkEndpoint(
            baseUrl: remote,
            backend: ollama
                ? BrainBackend.ollama
                : BrainBackend.openAiCompatible,
          );
          addTearDown(() async {
            client.release();
            await work;
            await client.cleanup();
          });
          await client.entered.future;
          expect(PrivacyGuard.debugLocalOnlyOverride, true);
          expect(client.requests, 1);
          await assertRows(1);
          client.release();
          final outcome = await work;
          if (result == 'success') {
            expect(outcome, isA<EndpointCheckOk>());
            expect((outcome as EndpointCheckOk).models, ['fixture-model']);
          } else {
            final failed = outcome as EndpointCheckFailed;
            expect(
              failed.reason,
              result == 'throw'
                  ? EndpointCheckFailure.unreachable
                  : result == 'status'
                  ? EndpointCheckFailure.httpError
                  : EndpointCheckFailure.badResponse,
            );
            if (result == 'status') expect(failed.statusCode, 400);
          }
          await assertRows(1);
          expect(client.requests, 1);
          // Direct assistant lacks local-only gate; intercepted request only,
          // not permission for real remote traffic or a privacy guarantee.
        },
      );
    }
  }
  test(
    'assistant invalid URI shape has neither captured GET nor row',
    () async {
      final client = CheckClient('https://never-used.invalid');
      addTearDown(client.cleanup);
      final result = await EndpointAssistant(client: client)
          .checkEndpoint(baseUrl: '', backend: BrainBackend.ollama);
      expect(
        (result as EndpointCheckFailed).reason,
        EndpointCheckFailure.invalidUrl,
      );
      expect(client.requests, 0);
      expect(client.entered.isCompleted, false);
      await assertRows(0);
    },
  );
  test(
    'detectLocalOllama shares exact default GET and zero-amount record site',
    () async {
      final client = CheckClient(
        'http://localhost:11434/api/tags',
        ollama: true,
      );
      final work = EndpointAssistant(client: client).detectLocalOllama();
      addTearDown(() async {
        client.release();
        await work;
        await client.cleanup();
      });
      await client.entered.future;
      await assertRows(1, host: 'localhost');
      client.release();
      final detection = await work;
      expect(detection!.baseUrl, EndpointAssistant.ollamaDefaultBaseUrl);
      expect(detection.models, ['fixture-model']);
      await assertRows(1, host: 'localhost');
    },
  );
  for (final result in ['success', 'throw', 'status', 'refused']) {
    test(
      'diagnostics $result captured header-only GET has no egress row',
      () async {
        final client = CheckClient(
          remote,
          diagnostics: true,
          status: result == 'status' ? 400 : 200,
        )..fail = result == 'throw';
        PrivacyGuard.debugLocalOnlyOverride = result == 'refused';
        final work = Diagnostics.providerReachable(
          client: client,
          settings: () async => const BrainSettings(
            backend: BrainBackend.ollama,
            baseUrl: remote,
            model: 'synthetic-model',
          ),
        );
        addTearDown(() async {
          client.release();
          await work;
          await client.cleanup();
        });
        if (result != 'refused') {
          await client.entered.future;
          expect(client.requests, 1);
          await assertRows(0);
          client.release();
        }
        final outcome = await work;
        expect(
          outcome.status,
          result == 'success'
              ? CheckStatus.pass
              : result == 'throw'
              ? CheckStatus.unknown
              : CheckStatus.fail,
        );
        if (result == 'success') {
          expect(outcome.fixEn, contains('not verified'));
        }
        if (result == 'refused') {
          expect(client.requests, 0);
          expect(client.entered.isCompleted, false);
        } else if (result != 'throw') {
          await client
              .cancelled
              .future; // Await actual header-body cancellation.
        }
        await assertRows(0);
        expect(
          client.closed,
          false,
        ); // Injected shared client remains caller-owned.
      },
    );
  }
}
