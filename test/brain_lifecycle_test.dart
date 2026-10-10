import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/brain.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/tools.dart';

class HeldProvider extends LlmProvider {
  HeldProvider({this.native = true});
  final bool native;
  @override
  String get name => 'synthetic';
  @override
  bool get supportsNativeTools => native;
  Future<String> Function(List<LlmMessage>)? text;
  Future<LlmResponse> Function(List<LlmMessage>)? tools;
  Stream<String> Function(List<LlmMessage>)? stream;
  final submitted = <List<LlmMessage>>[];
  @override
  Future<String> chat(List<LlmMessage> messages) {
    submitted.add(messages);
    return text?.call(messages) ?? Future.value('summary');
  }

  @override
  Future<LlmResponse> chatWithTools(List<LlmMessage> messages) {
    if (!native) return super.chatWithTools(messages);
    submitted.add(messages);
    return tools?.call(messages) ?? Future.value(const LlmResponse('fresh'));
  }

  @override
  Stream<String> chatStream(List<LlmMessage> messages) {
    submitted.add(messages);
    return stream?.call(messages) ?? Stream.value('fresh');
  }
}

void main() {
  for (final stage in ['ask', 'plain', 'tool']) {
    for (final error in [false, true]) {
      test(
        'entered $stage reset ${error ? "error" : "success"} no old history/tool',
        () async {
          final entered = Completer<void>(), release = Completer<LlmResponse>();
          final plain = Completer<String>();
          final p = HeldProvider(native: stage != 'plain');
          p.tools = (_) {
            entered.complete();
            return release.future;
          };
          p.text = (_) {
            entered.complete();
            return plain.future;
          };
          final b = Brain(provider: p, persona: 'CUSTOM PERSONA');
          final system = b.history.first.content;
          final pending = stage == 'tool'
              ? b.toolResult('click', 'old result')
              : b.ask('old user');
          await entered.future;
          b.reset();
          expect(b.history.length, 1);
          expect(b.history.first.content, system);
          expect(b.memory, isNull);
          if (error) {
            if (stage == 'plain') {
              plain.completeError(StateError('old'));
            } else {
              release.completeError(StateError('old'));
            }
          } else {
            if (stage == 'plain') {
              plain.complete('old plain');
            } else {
              release.complete(
                LlmResponse('old answer', toolCall: ToolCall('click', {})),
              );
            }
          }
          final reply = await pending;
          expect(reply.spoken, '');
          expect(reply.toolCall, isNull);
          expect(b.history.length, 1);
          p.tools = null;
          p.text = null;
          expect(
            (await b.ask('new user')).spoken,
            stage == 'plain' ? 'summary' : 'fresh',
          );
          expect(
            b.history.map((m) => m.content).join(),
            isNot(contains('old user')),
          );
        },
      );
    }
  }
  for (final error in [false, true]) {
    test(
      'entered stream reset ${error ? "error" : "tokens"} no old callback/assistant',
      () async {
        final body = StreamController<String>();
        final entered = Completer<void>();
        var cancels = 0;
        body.onCancel = () => cancels++;
        final p = HeldProvider()
          ..stream = (_) {
            entered.complete();
            return body.stream;
          };
        final b = Brain(provider: p);
        final tokens = <String>[];
        final pending = b.askStreaming('old', onToken: tokens.add);
        await entered.future;
        b.reset();
        if (error) {
          body.addError(StateError('late'));
        } else {
          body.add('old token');
        }
        final result = await pending;
        expect(result.spoken, '');
        expect(result.toolCall, isNull);
        expect(tokens, isEmpty);
        expect(b.history.length, 1);
        expect(cancels, 1);
        await body.close();
      },
    );
  }
  test('reset inside onToken stops further callbacks/tool/history', () async {
    final p = HeldProvider()
      ..stream = (_) => Stream.fromIterable([
        'first',
        'second',
        '{"tool":"click","arguments":{}}',
      ]);
    final b = Brain(provider: p);
    var calls = 0;
    final reply = await b.askStreaming(
      'old',
      onToken: (_) {
        calls++;
        b.reset();
      },
    );
    expect(calls, 1);
    expect(reply.spoken, '');
    expect(reply.toolCall, isNull);
    expect(b.history.length, 1);
  });
  for (final error in [false, true]) {
    test(
      'actual overflow summary reset ${error ? "error" : "success"} cannot restore memory',
      () async {
        final entered = Completer<void>(), release = Completer<String>();
        var summaries = 0;
        final p = HeldProvider();
        final b = Brain(provider: p, persona: 'KEEP PERSONA');
        final system = b.history.first.content;
        for (var i = 0; i < 21; i++) {
          await b.ask('seed$i');
        }
        expect(b.memory, isNotNull);
        p.text = (_) {
          summaries++;
          entered.complete();
          return release.future;
        };
        final pending = b.ask('entered overflow');
        await entered.future;
        b.reset();
        if (error) {
          release.completeError(StateError('old summary'));
        } else {
          release.complete('old memory');
        }
        expect((await pending).spoken, '');
        expect(b.memory, isNull);
        expect(b.history.length, 1);
        expect(b.history.first.content, system);
        p.text = null;
        await b.ask('fresh');
        expect(summaries, 1);
        expect(b.memory, isNull);
      },
    );
  }
  test(
    'concurrent summary waiters share owned batch and preserve new overflow',
    () async {
      final entered = Completer<void>(), release = Completer<String>();
      final p = HeldProvider();
      final b = Brain(provider: p);
      for (var i = 0; i < 20; i++) {
        await b.ask('seed$i');
      }
      var summaries = 0;
      p.text = (_) {
        summaries++;
        if (summaries == 1) {
          entered.complete();
          return release.future;
        }
        return Future.value('later memory');
      };
      final first = b.ask('first concurrent');
      await entered.future;
      final second = b.ask('second concurrent');
      await Future<void>.delayed(Duration.zero);
      expect(summaries, 1);
      release.complete('owned memory');
      await Future.wait([first, second]);
      expect(b.memory, 'owned memory');
      await b.ask('third');
      expect(summaries, 2);
      expect(b.memory, 'later memory');
      expect(
        b.history.where((m) => m.content.startsWith(Brain.memoryPrefix)).length,
        1,
      );
    },
  );
  test(
    'submitted snapshots and images detached immutable through appends/reset',
    () async {
      final entered = Completer<void>(), release = Completer<LlmResponse>();
      final p = HeldProvider()
        ..tools = (_) {
          entered.complete();
          return release.future;
        };
      final b = Brain(provider: p);
      final images = ['synthetic image'];
      final pending = b.ask('old', images: images);
      await entered.future;
      final snapshot = p.submitted.single;
      images.add('late mutation');
      expect(snapshot.last.images, ['synthetic image']);
      expect(
        () => snapshot.add(LlmMessage('user', 'bad')),
        throwsUnsupportedError,
      );
      expect(() => snapshot.last.images.add('bad'), throwsUnsupportedError);
      b.reset();
      p.tools = null;
      await b.ask('fresh');
      expect(snapshot.last.content, 'old');
      expect(snapshot.length, 2);
      expect(snapshot.last.images, ['synthetic image']);
      release.complete(const LlmResponse('late'));
      await pending;
      expect(b.history.map((m) => m.content), isNot(contains('late')));
    },
  );
  test(
    'current provider error propagates and reset clears manual memory',
    () async {
      final b = Brain(
        provider: HeldProvider()
          ..tools = (_) async => throw StateError('current'),
      );
      b.memory = 'old';
      await expectLater(b.ask('user'), throwsStateError);
      b.reset();
      expect(b.memory, isNull);
      expect(b.history.length, 1);
    },
  );
  test('reset detaches old summary owner while new session commits independent summary', () async {
    final p = HeldProvider();
    final b = Brain(provider: p);
    for (var i = 0; i < 20; i++) {
      await b.ask('old$i');
    }
    final oldEntered = Completer<void>(), oldRelease = Completer<String>();
    p.text = (_) {
      oldEntered.complete();
      return oldRelease.future;
    };
    final old = b.ask('old summary');
    await oldEntered.future;
    b.reset();
    p.text = (_) async => 'new session memory';
    for (var i = 0; i < 22; i++) {
      await b.ask('new$i');
    }
    expect(b.memory, 'new session memory');
    oldRelease.complete('late old memory');
    expect((await old).spoken, '');
    expect(b.memory, 'new session memory');
    expect(
      b.history.map((m) => m.content).join(),
      isNot(contains('late old memory')),
    );
  });
  test(
    'concurrent failed summary leaves batch for one subsequent retry',
    () async {
      final p = HeldProvider();
      final b = Brain(provider: p);
      for (var i = 0; i < 20; i++) {
        await b.ask('s$i');
      }
      final entered = Completer<void>(), release = Completer<String>();
      var calls = 0;
      p.text = (_) {
        calls++;
        if (calls == 1) {
          entered.complete();
          return release.future;
        }
        return Future.value('retry memory');
      };
      final a = b.ask('a');
      await entered.future;
      final c = b.ask('c');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      release.completeError(StateError('summary error'));
      await Future.wait([a, c]);
      expect(b.memory, isNull);
      await b.ask('retry');
      expect(calls, 2);
      expect(b.memory, 'retry memory');
    },
  );
}
