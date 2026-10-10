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
    final retry1 = c.retry(), retry2 = c.retry();
    expect(retry1, same(work));
    expect(retry2, same(work));
    var settled = 0;
    retry1.then((_) => settled++);
    retry2.then((_) => settled++);
    await Future<void>.value();
    expect(settled, 0);
    expect(calls, 1);
    c.dispose();
    final before = notifications;
    release.complete();
    await Future.wait([work, retry1, retry2]);
    expect(settled, 2);
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
    'dispose before scheduled entry prevents all notification and reload',
    () async {
      var calls = 0, notifications = 0;
      final c = HostReloadController(
        reload: () async {
          calls++;
        },
      );
      c.addListener(() => notifications++);
      final work = c.reload();
      c.dispose();
      await work;
      expect(calls, 0);
      expect(notifications, 0);
    },
  );
  for (final stage in ['load', 'refusal']) {
    for (final fail in [false, true]) {
      test('actual host $stage retry joins until release fail=$fail', () async {
        final entered = Completer<void>(), release = Completer<void>();
        var calls = 0;
        final host = BrainHostState(
          load: () async {
            if (stage == 'load') {
              calls++;
              entered.complete();
              await release.future;
              if (fail) throw StateError('private');
            }
            return const BrainSettings(
              backend: BrainBackend.ollama,
              baseUrl: 'http://localhost:11434',
              model: 'synthetic',
            );
          },
          refusal: (_) async {
            if (stage == 'refusal') {
              calls++;
              entered.complete();
              await release.future;
              if (fail) throw StateError('private');
            }
            return null;
          },
          build: (_) => Brain(provider: FakeProvider()),
        );
        final c = HostReloadController(reload: host.reload);
        Future<void>? reentrant;
        c.addListener(() {
          if (c.loading) reentrant = c.retry();
        });
        final work = c.reload();
        await entered.future;
        final a = c.retry(), b = c.retry();
        expect(a, same(work));
        expect(b, same(work));
        expect(reentrant, same(work));
        var settled = 0;
        a.then((_) => settled++);
        b.then((_) => settled++);
        await Future<void>.value();
        expect(settled, 0);
        expect(calls, 1);
        release.complete();
        await Future.wait([work, a, b]);
        expect(settled, 2);
        expect(c.loading, false);
        expect(c.failed, fail);
        c.dispose();
        host.brain.dispose();
        host.refusedReason.dispose();
        host.remoteActive.dispose();
      });
    }
  }
  for (final phase in ['loading', 'success', 'failure']) {
    test(
      'reentrant disposal during $phase is safe and blocks later entry',
      () async {
        var calls = 0, notifications = 0;
        final c = HostReloadController(
          reload: () async {
            calls++;
            if (phase == 'failure') throw StateError('private');
          },
        );
        c.addListener(() {
          notifications++;
          if (phase == 'loading' || !c.loading) {
            c.dispose();
            c.dispose();
          }
        });
        await c.reload();
        final before = notifications;
        await c.retry();
        await c.reload();
        c.dispose();
        expect(notifications, before);
        expect(calls, phase == 'loading' ? 0 : 1);
      },
    );
  }
  for (final sync in [false, true]) {
    test('sync=$sync failure retry observes settled status', () async {
      final c = HostReloadController(
        reload: () {
          if (sync) throw StateError('private');
          return Future.error(StateError('private'));
        },
      );
      await c.retry();
      expect(c.failed, true);
      expect(c.loading, false);
      c.dispose();
    });
  }
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
