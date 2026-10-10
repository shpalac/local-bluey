import 'dart:async';
import 'dart:io';

import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/services/stt.dart';
import 'package:local_bluey/services/speech.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/services/diagnostics.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/data_registry.dart';

void main() {
  test(
    'read uncertainty prevents STT/TTS and diagnostic HTTP effects',
    () async {
      var calls = 0;
      final c = LocalOnlyPreferences(
        read: () async => throw StateError('private'),
        write: (_) async => true,
        remove: () async => true,
      );
      PrivacyGuard.debugPreferences = c;
      addTearDown(() => PrivacyGuard.debugPreferences = null);
      final client = MockClient((_) async {
        calls++;
        return http.Response('bad', 200);
      });
      const brain = BrainSettings(
        backend: BrainBackend.openAiCompatible,
        baseUrl: 'https://remote.invalid',
        model: 'fixture',
      );
      await expectLater(
        SpeechService(client: client).synthesize('synthetic', brain),
        throwsA(isA<PrivacyStorageException>()),
      );
      await expectLater(
        HttpSttProvider(client: client).transcribe(
          File('/tmp/nonexistent-synthetic'),
          const SttSettings(baseUrl: 'https://remote.invalid'),
        ),
        throwsA(isA<PrivacyStorageException>()),
      );
      final result = await Diagnostics.providerReachable(
        settings: () async => brain,
        client: client,
      );
      expect(result.status, CheckStatus.unknown);
      expect(calls, 0);
    },
  );
  test('successful write followed by failed reconciliation reports uncertainty then recovers', () async {
    bool? stored = false;
    var failRead = false;
    final c = LocalOnlyPreferences(
      read: () async {
        if (failRead) throw StateError('private');
        return stored;
      },
      write: (value) async {
        stored = value;
        failRead = true;
        return true;
      },
      remove: () async {
        stored = null;
        return true;
      },
    );
    await c.read();
    await expectLater(c.set(true), throwsA(isA<PrivacyStorageException>()));
    expect(stored, true);
    expect(c.value, isNull);
    failRead = false;
    expect(await c.read(), true);
    expect(c.value, true);
    await c.clear();
    expect(stored, isNull);
    expect(c.value, false);
  });
  for (final stage in ['read', 'write', 'remove']) {
    test('entered $stage cannot undo completed registry clear', () async {
      bool? stored = true;
      var hold = true;
      final entered = Completer<void>(), release = Completer<void>();
      Future<void> pause(String op) async {
        if (hold && op == stage) {
          hold = false;
          entered.complete();
          await release.future;
        }
      }

      final c = LocalOnlyPreferences(
        read: () async {
          final value = stored;
          await pause('read');
          return value;
        },
        write: (value) async {
          await pause('write');
          stored = value;
          return true;
        },
        remove: () async {
          await pause('remove');
          stored = null;
          return true;
        },
      );
      PrivacyGuard.debugPreferences = c;
      addTearDown(() => PrivacyGuard.debugPreferences = null);
      final old = stage == 'read'
          ? c.read()
          : stage == 'write'
          ? c.set(true)
          : c.clear();
      final oldHandled = old.then<void>(
        (_) {},
        onError: (Object error) {
          expect(error, isA<PrivacyStorageException>());
        },
      );
      await entered.future;
      final clear = DataRegistry.stores
          .firstWhere((s) => s.id == 'privacy')
          .clear();
      release.complete();
      await Future.wait([oldHandled, clear]);
      expect(stored, isNull);
      expect(c.value, false);
      await c.set(true);
      expect(stored, true);
      expect(c.value, true);
      expect(
        await PrivacyGuard.refusalForUrl('https://remote.invalid'),
        isNotNull,
      );
      await c.set(false);
      expect(
        await PrivacyGuard.refusalForUrl('https://remote.invalid'),
        isNull,
      );
    });
  }
  for (final op in ['read', 'write', 'remove']) {
    for (final throwing in [false, true]) {
      if (op == 'read' && !throwing) continue;
      test(
        '$op ${throwing ? 'throw' : 'false'} retains honest state/retries',
        () async {
          bool? stored = true;
          var fail = false;
          bool failure() {
            if (throwing) throw StateError('private sentinel');
            return false;
          }

          final c = LocalOnlyPreferences(
            read: () async {
              if (fail && op == 'read') failure();
              return stored;
            },
            write: (v) async {
              if (fail && op == 'write') return failure();
              stored = v;
              return true;
            },
            remove: () async {
              if (fail && op == 'remove') return failure();
              stored = null;
              return true;
            },
          );
          await c.read();
          fail = true;
          await expectLater(
            op == 'read'
                ? c.read()
                : op == 'write'
                ? c.set(false)
                : c.clear(),
            throwsA(
              isA<PrivacyStorageException>().having(
                (e) => e.toString(),
                'safe',
                isNot(contains('private sentinel')),
              ),
            ),
          );
          expect(stored, true);
          expect(c.value, op == 'read' ? isNull : true);
          fail = false;
          await c.clear();
          expect(c.value, false);
          expect(stored, isNull);
          await c.set(true);
          expect(c.value, true);
        },
      );
    }
  }
  test(
    'uncertain read never authorizes remote, debug override unchanged',
    () async {
      final c = LocalOnlyPreferences(
        read: () async => throw StateError('private'),
        write: (_) async => true,
        remove: () async => true,
      );
      PrivacyGuard.debugPreferences = c;
      addTearDown(() {
        PrivacyGuard.debugPreferences = null;
        PrivacyGuard.debugLocalOnlyOverride = null;
      });
      await expectLater(
        PrivacyGuard.refusalForUrl('https://remote.invalid'),
        throwsA(isA<PrivacyStorageException>()),
      );
      PrivacyGuard.debugLocalOnlyOverride = true;
      expect(await PrivacyGuard.isLocalOnly(), true);
      PrivacyGuard.debugLocalOnlyOverride = false;
      expect(await PrivacyGuard.isLocalOnly(), false);
    },
  );
  test(
    'queued old choice invalidated but fresh choice after clear persists',
    () async {
      bool? stored;
      final entered = Completer<void>(), release = Completer<void>();
      var hold = true;
      final c = LocalOnlyPreferences(
        read: () async {
          if (hold) {
            hold = false;
            entered.complete();
            await release.future;
          }
          return stored;
        },
        write: (v) async {
          stored = v;
          return true;
        },
        remove: () async {
          stored = null;
          return true;
        },
      );
      final read = c.read();
      final readHandled = read.then<void>((_) {}, onError: (Object _) {});
      await entered.future;
      final old = c.set(true), clear = c.clear(), fresh = c.set(true);
      release.complete();
      await Future.wait([readHandled, old, clear, fresh]);
      expect(stored, true);
      expect(c.value, true);
      final reads = await Future.wait([c.read(), c.read()]);
      expect(reads, [true, true]);
    },
  );
}
