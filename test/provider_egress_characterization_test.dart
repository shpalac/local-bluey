import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/ollama_provider.dart';
import 'package:local_bluey/llm/openai_compatible_provider.dart';
import 'package:local_bluey/llm/tools.dart';
import 'package:local_bluey/services/egress_monitor.dart';

// Synthetic captured request bytes, never real socket/wire/receipt evidence.
const baseUrl = 'https://fixture.invalid/v1';
const model = 'synthetic-model';
const messages = [
  LlmMessage('user', 'שלום café 😀', images: ['AQI=']),
];

Map<String, dynamic> payload(
  bool ollama, {
  bool tools = false,
  bool stream = false,
}) => {
  'model': model,
  if (ollama || stream) 'stream': stream,
  if (tools) 'tools': kToolsAsFunctions(),
  'messages': [
    if (ollama)
      messages.single.toJson()
    else
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': messages.single.content},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,AQI='},
          },
        ],
      },
  ],
};

/// No IO client or network fallback. Unexpected requests fail locally.
class CapturedClient extends http.BaseClient {
  CapturedClient(
    this.ollama,
    this.expected, {
    this.status = 200,
    this.malformed = false,
  });
  final bool ollama;
  final Map<String, dynamic> expected;
  final int status;
  final bool malformed;
  final entered = Completer<void>();
  final responseGate = Completer<void>();
  final requests = <List<int>>[];
  bool throwTransport = false;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed ||
        request.method != 'POST' ||
        request.url.toString() !=
            '$baseUrl/${ollama ? 'api/chat' : 'chat/completions'}') {
      throw StateError('network forbidden: unexpected fixture request');
    }
    expect(request.headers['content-type'], startsWith('application/json'));
    final bytes = await request.finalize().toBytes();
    expect(utf8.decode(bytes), jsonEncode(expected));
    requests.add(bytes);
    if (!entered.isCompleted) entered.complete();
    await responseGate.future;
    // Generic failure is deliberately nonretryable: no timer/backoff needed.
    if (throwTransport) throw StateError('synthetic transport failure');
    final stream = expected['stream'] == true;
    final body = malformed
        ? '{'
        : stream
        ? ollama
              ? '{"message":{"content":"fixture answer"},"done":true}\n'
              : 'data: {"choices":[{"delta":{"content":"fixture answer"}}]}\n\ndata: [DONE]\n\n'
        : ollama
        ? '{"message":{"content":"fixture answer"}}'
        : '{"choices":[{"message":{"content":"fixture answer"}}]}';
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  }

  void release() {
    if (!responseGate.isCompleted) responseGate.complete();
  }

  @override
  void close() => closed = true;
}

LlmProvider provider(bool ollama, http.Client client) => ollama
    ? OllamaProvider(baseUrl: baseUrl, model: model, client: client)
    : OpenAiCompatibleProvider(baseUrl: baseUrl, model: model, client: client);

Future<String> call(LlmProvider value, bool tools) async => tools
    ? (await value.chatWithTools(messages)).text
    : await value.chat(messages);

Future<void> assertRows(CapturedClient client, int count) async {
  // load is a queue barrier after older unawaited record calls, not a sleep.
  await EgressMonitor.instance.load();
  expect(EgressMonitor.instance.historyAvailable, true);
  final rows = EgressMonitor.instance.entries;
  expect(rows, hasLength(count));
  for (final row in rows) {
    expect(row.host, 'fixture.invalid');
    expect(row.kind, 'brain');
    expect(row.bytes, jsonEncode(client.expected).length);
    expect(row.bytes, lessThan(client.requests.first.length));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory telemetry;
  setUp(() async {
    // No preferences/privacy global is read or changed by these provider calls.
    telemetry = await Directory.systemTemp.createTemp('provider-egress-482-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => telemetry.path);
    await EgressMonitor.instance.clear();
  });
  tearDown(() async {
    await EgressMonitor.instance.load();
    await EgressMonitor.instance.clear();
    expect(EgressMonitor.instance.entries, isEmpty);
    expect(await telemetry.list().toList(), isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    await telemetry.delete();
    expect(await telemetry.exists(), false);
  });

  for (final ollama in [false, true]) {
    final backend = ollama ? 'Ollama' : 'OpenAI';
    test('$backend captured stream enters but records no metadata', () async {
      final client = CapturedClient(ollama, payload(ollama, stream: true));
      final work = provider(ollama, client).chatStream(messages).toList();
      addTearDown(() async {
        client.release();
        await work;
        client.close();
      });
      await client.entered.future;
      expect(client.requests, hasLength(1));
      await assertRows(client, 0);
      client.release();
      expect(await work, ['fixture answer']);
      await assertRows(client, 0);
    });
    for (final tools in [false, true]) {
      final method = tools ? 'chatWithTools' : 'chat';
      for (final result in ['success', 'throw', 'status', 'json']) {
        test('$backend $method held/$result metadata is response-observed', () async {
          final client = CapturedClient(
            ollama,
            payload(ollama, tools: tools),
            status: result == 'status' ? 400 : 200,
            malformed: result == 'json',
          );
          client.throwTransport = result == 'throw';
          // Attach error handling before releasing the deterministic response.
          Object? failure;
          String? answer;
          final work = call(provider(ollama, client), tools).then<void>(
            (value) => answer = value,
            onError: (Object error) {
              failure = error;
            },
          );
          addTearDown(() async {
            client.release();
            await work;
            client.close();
          });
          await client.entered.future;
          expect(client.requests, hasLength(1));
          await assertRows(client, 0);
          client.release();
          await work;
          if (result == 'success') {
            expect(answer, 'fixture answer');
            expect(failure, isNull);
          } else {
            expect(answer, isNull);
            expect(
              failure,
              result == 'throw'
                  ? isA<StateError>()
                  : result == 'status'
                  ? isA<LlmException>()
                  : isA<FormatException>(),
            );
          }
          expect(client.requests, hasLength(1));
          await assertRows(client, result == 'throw' ? 0 : 1);
        });
      }
      test(
        '$backend $method two explicit invocations retain two rows',
        () async {
          final client = CapturedClient(ollama, payload(ollama, tools: tools));
          client.release();
          addTearDown(client.close);
          final value = provider(ollama, client);
          expect(await call(value, tools), 'fixture answer');
          expect(await call(value, tools), 'fixture answer');
          expect(client.requests, hasLength(2));
          await assertRows(client, 2);
          // This is not a retry/idempotency, socket-byte, privacy or receipt test.
        },
      );
    }
  }
}
