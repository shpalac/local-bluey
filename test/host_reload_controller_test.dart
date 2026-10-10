import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/host_reload_controller.dart';
import 'package:local_bluey/services/brain_host.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/llm/brain.dart';
import 'package:local_bluey/llm/llm_provider.dart';

class FakeProvider extends LlmProvider {
  @override
  String get name => 'synthetic';
  @override
  Future<String> chat(List<LlmMessage> messages) async =>
      throw StateError('no network');
}

void main() {
  for (final stage in ['load', 'refusal', 'build']) {
    test(
      'entered $stage failure contained with explicit retry, retains snapshot',
      () async {
        var fail = false;
        final entered = Completer<void>(), release = Completer<void>();
        final host = BrainHostState(
          load: () async {
            if (fail && stage == 'load') {
              entered.complete();
              await release.future;
              throw StateError('private load');
            }
            return const BrainSettings(
              backend: BrainBackend.ollama,
              baseUrl: 'http://localhost:11434',
              model: 'synthetic',
            );
          },
          refusal: (_) async {
            if (fail && stage == 'refusal') {
              entered.complete();
              await release.future;
              throw StateError('private refusal');
            }
            return null;
          },
          build: (_) {
            if (fail && stage == 'build') throw StateError('private build');
            return Brain(provider: FakeProvider());
          },
        );
        final c = HostReloadController(reload: host.reload);
        await c.reload();
        final prior = host.brain.value;
        fail = true;
        final work = c.reload();
        if (stage != 'build') {
          await entered.future;
          expect(c.loading, true);
          release.complete();
        }
        await work;
        expect(c.failed, true);
        expect(host.brain.value, same(prior));
        fail = false;
        await c.retry();
        expect(c.failed, false);
        expect(c.loading, false);
        c.dispose();
        host.brain.dispose();
        host.refusedReason.dispose();
        host.remoteActive.dispose();
      },
    );
  }
  for (final oldError in [true, false]) {
    for (final freshError in [true, false]) {
      test(
        'old ${oldError ? 'error' : 'success'} cannot overwrite fresh ${freshError ? 'error' : 'success'}',
        () async {
          final entered = Completer<void>(), release = Completer<void>();
          var calls = 0;
          final c = HostReloadController(
            reload: () async {
              if (calls++ == 0) {
                entered.complete();
                await release.future;
                if (oldError) throw StateError('old');
              } else if (freshError) {
                throw StateError('fresh');
              }
            },
          );
          final old = c.reload();
          await entered.future;
          await c.reload();
          release.complete();
          await old;
          expect(c.failed, freshError);
          expect(c.loading, false);
          c.dispose();
        },
      );
    }
  }
  test('retries coalesce and disposal contains late entered error without notification', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var calls = 0, notifications = 0;
    final c = HostReloadController(
      reload: () async {
        calls++;
        entered.complete();
        await release.future;
        throw StateError('private');
      },
    );
    c.addListener(() => notifications++);
    final work = c.reload();
    await entered.future;
    await Future.wait([c.retry(), c.retry()]);
    expect(calls, 1);
    c.dispose();
    final before = notifications;
    release.complete();
    await work;
    expect(notifications, before);
    await c.retry();
    expect(calls, 1);
  });
  test(
    'reentrant fresh reload before entry cannot start older operation',
    () async {
      var calls = 0, reentered = false;
      final c = HostReloadController(
        reload: () async {
          calls++;
        },
      );
      c.addListener(() {
        if (!reentered) {
          reentered = true;
          c.reload();
        }
      });
      await c.reload();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(c.loading, false);
      c.dispose();
    },
  );
  test(
    'actual Mac source wiring routes five callers and both rendered routes',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final mac = source.substring(
        source.indexOf('class _MacHomeState'),
        source.indexOf('class IosHome'),
      );
      expect('unawaited(_hostReload.reload());'.allMatches(mac).length, 5);
      expect(mac, isNot(contains('BrainHost.reload()')));
      expect(
        'HostReloadNotice(controller: _hostReload)'.allMatches(mac).length,
        2,
      );
      expect(mac, contains('_hostReload.dispose();'));
      expect(
        'if (saved ?? false) unawaited(_hostReload.reload());'
            .allMatches(mac)
            .length,
        2,
      );
      expect(
        'setState(() => _showOnboarding = true)'.allMatches(mac).length,
        greaterThanOrEqualTo(3),
      );
    },
  );
}
