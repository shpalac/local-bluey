import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/ollama_provider.dart';
import 'package:local_bluey/llm/openai_compatible_provider.dart';
import 'package:local_bluey/services/egress_monitor.dart';

const base = 'https://retry-fixture.invalid/v1';
const input = [LlmMessage('user', 'שלום retry')];

/// Controls only existing retry delays. Real filesystem Futures keep their
/// normal event-loop semantics, unlike flushing IO inside a fake_async zone.
class RetryTimer implements Timer {
  RetryTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool _active = true;
  @override
  bool get isActive => _active;
  @override
  int get tick => _active ? 0 : 1;
  @override
  void cancel() => _active = false;
  void fire() {
    expect(isActive, true);
    _active = false;
    callback();
  }
}

class TypedClient extends http.BaseClient {
  TypedClient(this.ollama, this.timeout, this.exhaust);
  final bool ollama, timeout, exhaust;
  final bodies = <String>[];
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed ||
        request.method != 'POST' ||
        request.url.toString() !=
            '$base/${ollama ? 'api/chat' : 'chat/completions'}') {
      throw StateError('network forbidden: unexpected fixture request');
    }
    final body = utf8.decode(await request.finalize().toBytes());
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    expect(decoded['messages'], [
      {'role': 'user', 'content': 'שלום retry'},
    ]);
    expect(decoded['model'], 'fixture-model');
    bodies.add(body);
    if (exhaust || bodies.length < 3) {
      if (timeout) throw TimeoutException('synthetic timeout');
      throw const SocketException('synthetic socket');
    }
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          ollama
              ? '{"message":{"content":"fixture answer"}}'
              : '{"choices":[{"message":{"content":"fixture answer"}}]}',
        ),
      ),
      200,
    );
  }

  @override
  void close() => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory telemetry;
  setUp(() async {
    telemetry = await Directory.systemTemp.createTemp('retry-egress-491-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => telemetry.path);
    await EgressMonitor.instance.clear();
  });
  tearDown(() async {
    await EgressMonitor.instance.load();
    await EgressMonitor.instance.clear();
    expect(await telemetry.list().toList(), isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await telemetry.delete();
    expect(await telemetry.exists(), false);
  });
  for (final ollama in [false, true]) {
    for (final tools in [false, true]) {
      for (final timeout in [false, true]) {
        for (final exhaust in [false, true]) {
          test(
            '${ollama ? "Ollama" : "OpenAI"} tools=$tools timeout=$timeout exhaust=$exhaust attempted sends versus metadata',
            () async {
              final client = TypedClient(ollama, timeout, exhaust);
              final delays = <RetryTimer>[];
              final entered = [
                Completer<RetryTimer>(),
                Completer<RetryTimer>(),
              ];
              String? answer;
              Object? error;
              final provider = ollama
                  ? OllamaProvider(
                      baseUrl: base,
                      model: 'fixture-model',
                      client: client,
                    )
                  : OpenAiCompatibleProvider(
                      baseUrl: base,
                      model: 'fixture-model',
                      client: client,
                    );
              final work = runZoned(
                () {
                  final call = tools
                      ? provider.chatWithTools(input).then((r) => r.text)
                      : provider.chat(input);
                  return call.then<void>(
                    (value) => answer = value,
                    onError: (Object failure) {
                      error = failure;
                    },
                  );
                },
                zoneSpecification: ZoneSpecification(
                  createTimer: (self, parent, zone, duration, callback) {
                    // No production seam. Override only known retry timer shapes.
                    if (duration == const Duration(milliseconds: 300) ||
                        duration == const Duration(milliseconds: 600)) {
                      final timer = RetryTimer(
                        duration,
                        () => zone.run(callback),
                      );
                      final index = delays.length;
                      delays.add(timer);
                      expect(index, lessThan(2));
                      entered[index].complete(timer);
                      return timer;
                    }
                    return parent.createTimer(zone, duration, callback);
                  },
                ),
              );
              addTearDown(() async {
                for (var i = 0; i < 2; i++) {
                  final timer = await entered[i].future;
                  if (timer.isActive) timer.fire();
                }
                await work;
                client.close();
              });
              for (var i = 0; i < 2; i++) {
                final timer = await entered[i].future;
                expect(timer.delay, Duration(milliseconds: i == 0 ? 300 : 600));
                expect(client.bodies, hasLength(i + 1));
                expect(answer, isNull);
                expect(error, isNull);
                await EgressMonitor.instance.load();
                expect(EgressMonitor.instance.entries, isEmpty);
                // No successor until explicit timer release, no wall-clock sleep.
                expect(client.bodies, hasLength(i + 1));
                timer.fire();
              }
              await work;
              await EgressMonitor.instance.load();
              expect(client.bodies, hasLength(3));
              expect(client.bodies.toSet(), hasLength(1));
              expect(delays, hasLength(2));
              expect(delays.every((t) => !t.isActive), true);
              if (exhaust) {
                expect(answer, isNull);
                expect(
                  error,
                  timeout ? isA<TimeoutException>() : isA<SocketException>(),
                );
                expect(EgressMonitor.instance.entries, isEmpty);
              } else {
                expect(answer, 'fixture answer');
                expect(error, isNull);
                final entry = EgressMonitor.instance.entries.single;
                expect(entry.host, 'retry-fixture.invalid');
                expect(entry.kind, 'brain');
                expect(entry.bytes, client.bodies.last.length);
                expect(
                  entry.bytes,
                  lessThan(utf8.encode(client.bodies.last).length),
                );
              }
              // Three intercepted attempts, at most one response-observed row.
              // No socket bytes, receipt, idempotency or billing claim.
            },
          );
        }
      }
    }
  }
}
