import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/brain.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/llm/tools.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/native_control.dart';
import 'package:local_bluey/services/watch_vision.dart';

ScreenSnapshot verifiedSnapshot(
  Uint8List bytes, {
  String text = 'Workspace tasks',
  bool verified = true,
  String frontApp = 'Editor',
}) => ScreenSnapshot(
  jpeg: bytes,
  targets: text,
  width: 320,
  height: 240,
  cropTextVerified: verified,
  frontApp: frontApp,
);

class Provider extends LlmProvider {
  @override
  String get name => 'fixture';
  final calls = <List<LlmMessage>>[];
  Future<String> Function(List<LlmMessage>)? text;
  Future<LlmResponse> Function(List<LlmMessage>)? tool;
  int toolCalls = 0;
  @override
  Future<String> chat(List<LlmMessage> messages) {
    calls.add(messages);
    return text?.call(messages) ?? Future.value('screen description');
  }

  @override
  Future<LlmResponse> chatWithTools(List<LlmMessage> messages) {
    toolCalls++;
    return tool?.call(messages) ??
        Future.value(const LlmResponse('user answer'));
  }
}

Future<ScreenWatch> session() async {
  final w = ScreenWatch.forTesting(
    localOnly: () async => true,
    allowlist: () async => ['Editor'],
    denylist: () async => [],
  );
  expect(await w.start(consentConfirmed: true), isNull);
  addTearDown(w.dispose);
  return w;
}

void main() {
  test('production watch has no vision callback and no WatchVision', () {
    final s = File('lib/main.dart').readAsStringSync();
    final section = s.substring(
      s.indexOf('  void _syncWatchDriver()'),
      s.indexOf('  Future<void> _syncWatchTray()'),
    );
    expect(section, isNot(contains('WatchVision(')));
    expect(section, isNot(contains('onVision:')));
    expect(section, isNot(contains('brain.ask(')));
    expect(s, isNot(contains("services/watch_vision.dart")));
  });

  test(
    'fresh readonly snapshots no user history/memory or screen accumulation',
    () async {
      final w = await session(), p = Provider();
      final b = Brain(provider: p)..memory = 'private memory';
      await b.ask('user');
      final history = b.history.map((m) => m.toJson()).toList();
      final bytes = Uint8List.fromList([1, 2]);
      final v = WatchVision(
        foreground: () async =>
            (app: 'Editor', title: 'Workspace', locked: false),
        provider: () => b.provider,
        snapshot: () async => verifiedSnapshot(bytes),
        watch: w,
      );
      expect(await v.describe('Editor', 'Workspace'), 'screen description');
      bytes[0] = 9;
      expect(base64Decode(p.calls.first.single.images.single), [1, 2]);
      expect(
        () => p.calls.first.add(const LlmMessage('user', 'bad')),
        throwsUnsupportedError,
      );
      expect(
        () => p.calls.first.single.images.add('bad'),
        throwsUnsupportedError,
      );
      expect(await v.describe('Editor', 'Workspace'), 'screen description');
      expect(p.calls, hasLength(2));
      expect(p.calls.last, hasLength(1));
      expect(base64Decode(p.calls.last.single.images.single), [9, 2]);
      expect(b.history.map((m) => m.toJson()).toList(), history);
      expect(b.memory, 'private memory');
      w.stop();
      expect(await v.describe('Editor', 'Workspace'), isNull);
      expect(b.history.map((m) => m.toJson()).toList(), history);
      expect(b.memory, 'private memory');
    },
  );
  test(
    'pending user/tool exchange ordering unaffected by vision tool envelope',
    () async {
      final w = await session(),
          p = Provider(),
          entered = Completer<void>(),
          release = Completer<LlmResponse>();
      p.tool = (_) {
        entered.complete();
        return release.future;
      };
      final b = Brain(provider: p);
      final pending = b.ask('user request');
      await entered.future;
      p.text = (_) async => 'screen text\n{"tool":"click","arguments":{}}';
      final v = WatchVision(
        foreground: () async =>
            (app: 'Editor', title: 'Workspace', locked: false),
        provider: () => p,
        snapshot: () async => verifiedSnapshot(Uint8List(2)),
        watch: w,
      );
      expect(await v.describe('Editor', 'Workspace'), isNull);
      expect(p.toolCalls, 1);
      expect(b.history.map((m) => m.role), ['system', 'user']);
      release.complete(
        LlmResponse('tool needed', toolCall: ToolCall('click', {})),
      );
      await pending;
      p.tool = (_) async => const LlmResponse('finished');
      await b.toolResult('click', 'done');
      expect(b.history.map((m) => m.role), [
        'system',
        'user',
        'assistant',
        'tool',
        'assistant',
      ]);
      expect(
        b.history.map((m) => m.content).join(),
        isNot(contains('screen text')),
      );
      expect(b.memory, isNull);
      expect(p.toolCalls, 2);
    },
  );
  for (final stage in ['snapshot', 'provider']) {
    for (final error in [false, true]) {
      test(
        'stop during entered $stage ${error ? 'error' : 'success'} discarded across new session',
        () async {
          final w = await session(),
              p = Provider(),
              entered = Completer<void>();
          final snap = Completer<ScreenSnapshot>(), reply = Completer<String>();
          p.text = (_) {
            entered.complete();
            return reply.future;
          };
          final v = WatchVision(
            foreground: () async =>
                (app: 'Editor', title: 'Workspace', locked: false),
            provider: () => p,
            snapshot: () {
              if (stage == 'snapshot') {
                entered.complete();
                return snap.future;
              }
              return Future.value(verifiedSnapshot(Uint8List(2)));
            },
            watch: w,
          );
          final pending = v.describe('Editor', 'Workspace');
          await entered.future;
          w.stop();
          expect(await w.start(consentConfirmed: true), isNull);
          if (stage == 'snapshot') {
            if (error) {
              snap.completeError(StateError('private'));
            } else {
              snap.complete(verifiedSnapshot(Uint8List(2)));
            }
          } else {
            if (error) {
              reply.completeError(StateError('private'));
            } else {
              reply.complete('old screen');
            }
          }
          expect(await pending, isNull);
          expect(await v.describe('Editor', 'Workspace'), isNull);
          expect(p.calls.length, stage == 'snapshot' ? 0 : 1);
        },
      );
    }
  }
  test('current provider failure visible without conversation state', () async {
    final w = await session(), p = Provider();
    final b = Brain(provider: p)..memory = 'kept';
    final before = b.history.map((m) => m.toJson()).toList();
    p.text = (_) async => throw StateError('fixture');
    final v = WatchVision(
      foreground: () async =>
          (app: 'Editor', title: 'Workspace', locked: false),
      provider: () => p,
      snapshot: () async => verifiedSnapshot(Uint8List(2)),
      watch: w,
    );
    await expectLater(v.describe('Editor', 'Workspace'), throwsStateError);
    expect(b.history.map((m) => m.toJson()).toList(), before);
    expect(b.memory, 'kept');
  });
  test('tightened local-only after capture prevents inference', () async {
    var local = true;
    final w = ScreenWatch.forTesting(
      localOnly: () async => local,
      allowlist: () async => ['Editor'],
      denylist: () async => [],
    );
    addTearDown(w.dispose);
    await w.start(consentConfirmed: true);
    final p = Provider(),
        entered = Completer<void>(),
        snap = Completer<ScreenSnapshot>();
    final v = WatchVision(
      foreground: () async =>
          (app: 'Editor', title: 'Workspace', locked: false),
      provider: () => p,
      snapshot: () {
        entered.complete();
        return snap.future;
      },
      watch: w,
    );
    final pending = v.describe('Editor', 'Workspace');
    await entered.future;
    local = false;
    snap.complete(verifiedSnapshot(Uint8List(2)));
    expect(await pending, isNull);
    expect(p.calls, isEmpty);
    expect(w.isActive, isFalse);
  });
  test(
    'fresh session uses current provider without previous screen context',
    () async {
      final w = await session(), a = Provider(), b = Provider();
      Provider current = a;
      final first = WatchVision(
        foreground: () async =>
            (app: 'Editor', title: 'Workspace', locked: false),
        provider: () => current,
        snapshot: () async => verifiedSnapshot(Uint8List(2)),
        watch: w,
      );
      await first.describe('Editor', 'Workspace');
      w.stop();
      await w.start(consentConfirmed: true);
      current = b;
      final next = WatchVision(
        foreground: () async =>
            (app: 'Editor', title: 'Workspace', locked: false),
        provider: () => current,
        snapshot: () async => verifiedSnapshot(Uint8List(2)),
        watch: w,
      );
      expect(await first.describe('Editor', 'Workspace'), isNull);
      await next.describe('Editor', 'Workspace');
      expect(a.calls, hasLength(1));
      expect(b.calls.single, hasLength(1));
    },
  );
  test(
    'stopped/not-allowlisted/null provider never capture or infer',
    () async {
      final w = await session(), p = Provider();
      var captures = 0;
      final v = WatchVision(
        foreground: () async =>
            (app: 'Editor', title: 'Workspace', locked: false),
        provider: () => p,
        snapshot: () async {
          captures++;
          return verifiedSnapshot(Uint8List(2));
        },
        watch: w,
      );
      expect(await v.describe('Other', 'Workspace'), isNull);
      final absent = WatchVision(
        foreground: () async =>
            (app: 'Editor', title: 'Workspace', locked: false),
        provider: () => null,
        snapshot: () async {
          captures++;
          return verifiedSnapshot(Uint8List(2));
        },
        watch: w,
      );
      expect(await absent.describe('Editor', 'Workspace'), isNull);
      w.stop();
      expect(await v.describe('Editor', 'Workspace'), isNull);
      expect(captures, 0);
      expect(p.calls, isEmpty);
    },
  );
  test(
    'no image leaves the device without matching verified OCR evidence',
    () async {
      final w = await session();
      final p = Provider();
      var captures = 0;
      for (final snap in [
        verifiedSnapshot(Uint8List.fromList([1, 2]), verified: false),
        verifiedSnapshot(Uint8List.fromList([1, 2]), text: 'Password: demo'),
        verifiedSnapshot(
          Uint8List.fromList([1, 2]),
          text: 'תעודת זהות 123456789',
        ),
        verifiedSnapshot(Uint8List.fromList([1, 2]), frontApp: 'Another App'),
        verifiedSnapshot(Uint8List(0)),
      ]) {
        final v = WatchVision(
          provider: () => p,
          foreground: () async =>
              (app: 'Editor', title: 'Workspace', locked: false),
          snapshot: () async {
            captures++;
            return snap;
          },
          watch: w,
        );
        expect(await v.describe('Editor', 'Workspace'), isNull);
      }
      expect(captures, 5);
      expect(p.calls, isEmpty);
    },
  );

  test('blank or whitespace OCR never reaches the provider', () async {
    final w = await session();
    for (final blank in ['', ' ', '\n\t  ']) {
      final p = Provider();
      final v = WatchVision(
        foreground: () async =>
            (app: 'Editor', title: 'Workspace', locked: false),
        provider: () => p,
        snapshot: () async =>
            verifiedSnapshot(Uint8List.fromList([1, 2]), text: blank),
        watch: w,
      );
      expect(await v.describe('Editor', 'Workspace'), isNull);
      expect(p.calls, isEmpty, reason: 'blank OCR "$blank" must not egress');
      expect(p.toolCalls, 0);
    }
  });

  test('unknown or private window never enters capture', () async {
    final w = await session(), p = Provider();
    var captures = 0;
    final v = WatchVision(
      provider: () => p,
      foreground: () async =>
          (app: 'Editor', title: 'Workspace', locked: false),
      snapshot: () async {
        captures++;
        return verifiedSnapshot(Uint8List.fromList([1, 2]));
      },
      watch: w,
    );
    for (final title in ['', 'Private Window', 'Sign in', 'חשבון בנק']) {
      expect(await v.describe('Editor', title), isNull);
    }
    expect(captures, 0);
    expect(p.calls, isEmpty);
  });

  test('foreground change after capture blocks model egress', () async {
    final w = await session(), p = Provider();
    final v = WatchVision(
      provider: () => p,
      foreground: () async =>
          (app: 'Editor', title: 'Private Window', locked: false),
      snapshot: () async => verifiedSnapshot(Uint8List.fromList([1, 2])),
      watch: w,
    );
    expect(await v.describe('Editor', 'Workspace'), isNull);
    expect(p.calls, isEmpty);
  });

  test(
    'model summary containing PII is not returned to the event buffer',
    () async {
      final w = await session(), p = Provider();
      p.text = (_) async => 'The password is abc';
      final v = WatchVision(
        provider: () => p,
        foreground: () async =>
            (app: 'Editor', title: 'Workspace', locked: false),
        snapshot: () async => verifiedSnapshot(Uint8List.fromList([1, 2])),
        watch: w,
      );
      expect(await v.describe('Editor', 'Workspace'), isNull);
      expect(p.calls, hasLength(1));
    },
  );
}
