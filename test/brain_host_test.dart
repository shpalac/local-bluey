import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/brain.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/services/brain_host.dart';
import 'package:local_bluey/services/settings_store.dart';

class FakeProvider extends LlmProvider {
  FakeProvider(this.name);
  @override
  final String name;
  @override
  Future<String> chat(List<LlmMessage> messages) async =>
      throw StateError('network forbidden');
}

BrainSettings settings(String name, {bool remote = false}) => BrainSettings(
  backend: BrainBackend.ollama,
  baseUrl: remote ? 'https://synthetic.invalid' : 'http://localhost:11434',
  model: name,
);
Brain build(BrainSettings value) => Brain(provider: FakeProvider(value.model));
void clean(BrainHostState s) {
  s.brain.dispose();
  s.refusedReason.dispose();
  s.remoteActive.dispose();
}

void expectState(BrainHostState s, String? name, String? reason, bool remote) {
  expect(s.brain.value?.provider.name, name);
  expect(s.refusedReason.value, reason);
  expect(s.remoteActive.value, remote);
}

void main() {
  for (final stage in ['load', 'refusal']) {
    for (final oldError in [false, true]) {
      for (final newRefused in [false, true]) {
        test(
          'old $stage ${oldError ? "error" : "success"} cannot overwrite newer ${newRefused ? "refused" : "allowed"}',
          () async {
            final entered = Completer<void>(), release = Completer<void>();
            var loads = 0;
            final host = BrainHostState(
              load: () async {
                final n = loads++;
                if (n == 0 && stage == 'load') {
                  entered.complete();
                  await release.future;
                  if (oldError) throw StateError('old load');
                }
                return settings(n == 0 ? 'old' : 'new', remote: n != 0);
              },
              refusal: (s) async {
                if (s.model == 'old' && stage == 'refusal') {
                  entered.complete();
                  await release.future;
                  if (oldError) throw StateError('old refusal');
                }
                return s.model == 'new'
                    ? (newRefused ? 'new refusal' : null)
                    : 'old refusal';
              },
              build: build,
            );
            final old = host.reload();
            await entered.future;
            await host.reload();
            expectState(
              host,
              newRefused ? null : 'new',
              newRefused ? 'new refusal' : null,
              !newRefused,
            );
            release.complete();
            await old;
            expectState(
              host,
              newRefused ? null : 'new',
              newRefused ? 'new refusal' : null,
              !newRefused,
            );
            await host.reload();
            expectState(
              host,
              newRefused ? null : 'new',
              newRefused ? 'new refusal' : null,
              !newRefused,
            );
            clean(host);
          },
        );
      }
    }
  }
  for (final stage in ['load', 'refusal', 'build']) {
    test('current $stage error retains prior coherent result', () async {
      var fail = false;
      final host = BrainHostState(
        load: () async {
          if (fail && stage == 'load') throw StateError('current');
          return settings('current', remote: true);
        },
        refusal: (_) async {
          if (fail && stage == 'refusal') throw StateError('current');
          return null;
        },
        build: (s) {
          if (fail && stage == 'build') throw StateError('current');
          return build(s);
        },
      );
      await host.reload();
      final original = host.brain.value;
      fail = true;
      await expectLater(host.reload(), throwsStateError);
      expect(identical(host.brain.value, original), isTrue);
      expectState(host, 'current', null, true);
      clean(host);
    });
  }
  test(
    'every notification reads coherent allowed/refused/local state',
    () async {
      var n = 0;
      final seen = <String>[];
      final host = BrainHostState(
        load: () async => settings('s${n++}', remote: n < 3),
        refusal: (s) async => s.model == 's1' ? 'blocked' : null,
        build: build,
      );
      void observe() {
        final name = host.brain.value?.provider.name;
        final refused = host.refusedReason.value;
        final remote = host.remoteActive.value;
        if (refused != null) {
          expect(name, isNull);
          expect(remote, isFalse);
        } else {
          expect(name, isNotNull);
          expect(remote, name == 's0');
        }
        seen.add('$name/$refused/$remote');
      }

      host.brain.addListener(observe);
      host.refusedReason.addListener(observe);
      host.remoteActive.addListener(observe);
      await host.reload();
      expectState(host, 's0', null, true);
      await host.reload();
      expectState(host, null, 'blocked', false);
      await host.reload();
      expectState(host, 's2', null, false);
      expect(seen.length, greaterThan(3));
      clean(host);
    },
  );
  test('listener reentrant reload owns next publication without old partial writes', () async {
    final nextLoad = Completer<BrainSettings>();
    var calls = 0;
    Future<void>? reloaded;
    final host = BrainHostState(
      load: () {
        if (calls++ == 0) return Future.value(settings('first', remote: true));
        return nextLoad.future;
      },
      refusal: (s) async => s.model == 'second' ? 'new blocked' : null,
      build: build,
    );
    host.brain.addListener(() {
      if (host.brain.value?.provider.name == 'first') {
        expectState(host, 'first', null, true);
        reloaded = host.reload();
      }
    });
    await host.reload();
    expectState(host, 'first', null, true);
    expect(reloaded, isNotNull);
    nextLoad.complete(settings('second', remote: true));
    await reloaded;
    expectState(host, null, 'new blocked', false);
    clean(host);
  });
  test(
    'reentrant build-triggered reload cannot publish superseded result',
    () async {
      var calls = 0;
      Future<void>? fresh;
      late BrainHostState host;
      host = BrainHostState(
        load: () async => settings(calls++ == 0 ? 'old' : 'new'),
        refusal: (_) async => null,
        build: (s) {
          if (s.model == 'old') fresh = host.reload();
          return build(s);
        },
      );
      await host.reload();
      await fresh;
      expectState(host, 'new', null, false);
      clean(host);
    },
  );
  test('old allowed remote refusal wait cannot revive newer refusal', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var n = 0;
    final host = BrainHostState(
      load: () async =>
          settings(n++ == 0 ? 'old allowed' : 'new blocked', remote: true),
      refusal: (s) async {
        if (s.model == 'old allowed') {
          entered.complete();
          await release.future;
          return null;
        }
        return 'current blocked';
      },
      build: build,
    );
    final old = host.reload();
    await entered.future;
    await host.reload();
    release.complete();
    await old;
    expectState(host, null, 'current blocked', false);
    clean(host);
  });
  test(
    'notifier-triggered second local reload wins over remote first',
    () async {
      var n = 0;
      Future<void>? fresh;
      final host = BrainHostState(
        load: () async =>
            settings(n++ == 0 ? 'remote' : 'local', remote: n == 1),
        refusal: (_) async => null,
        build: build,
      );
      host.remoteActive.addListener(() {
        if (host.remoteActive.value) {
          expectState(host, 'remote', null, true);
          fresh = host.reload();
        }
      });
      await host.reload();
      await fresh;
      expectState(host, 'local', null, false);
      clean(host);
    },
  );
  test(
    'first current construction error does not claim remote or clear refusal',
    () async {
      final host = BrainHostState(
        load: () async => settings('bad', remote: true),
        refusal: (_) async => null,
        build: (_) => throw StateError('bad construction'),
      );
      await expectLater(host.reload(), throwsStateError);
      expectState(host, null, null, false);
      clean(host);
    },
  );
  for (final failure in [false, true]) {
    test(
      'reentrant same remote ${failure ? "failure" : "success"} delivers pending listener',
      () async {
        var n = 0;
        final entered = Completer<void>(), release = Completer<void>();
        Future<void>? fresh;
        final host = BrainHostState(
          load: () async {
            if (n++ > 0) {
              entered.complete();
              await release.future;
              if (failure) throw StateError('new load');
            }
            return settings('remote$n', remote: true);
          },
          refusal: (_) async => null,
          build: build,
        );
        final observed = <bool>[];
        host.remoteActive.addListener(() {
          observed.add(host.remoteActive.value);
          expect(host.brain.value, isNotNull);
          expect(host.refusedReason.value, isNull);
        });
        host.brain.addListener(() {
          if (n == 1) fresh = host.reload();
        });
        await host.reload();
        await entered.future;
        expect(observed, isEmpty);
        final done = failure ? expectLater(fresh, throwsStateError) : fresh!;
        release.complete();
        await done;
        expect(observed, [true]);
        expect(host.remoteActive.value, isTrue);
        clean(host);
      },
    );
  }
  for (final failure in [false, true]) {
    test(
      'reentrant same refusal ${failure ? "failure" : "success"} delivers pending listener',
      () async {
        var n = 0;
        final entered = Completer<void>(), release = Completer<void>();
        Future<void>? fresh;
        final host = BrainHostState(
          load: () async {
            if (n++ == 2) {
              entered.complete();
              await release.future;
              if (failure) throw StateError('new load');
            }
            return settings('s$n', remote: true);
          },
          refusal: (s) async => s.model == 's1' ? null : 'blocked',
          build: build,
        );
        await host.reload();
        final observed = <String?>[];
        final remotes = <bool>[];
        host.refusedReason.addListener(() {
          observed.add(host.refusedReason.value);
          expectState(host, null, 'blocked', false);
        });
        host.remoteActive.addListener(
          () => remotes.add(host.remoteActive.value),
        );
        host.brain.addListener(() {
          if (n == 2) fresh = host.reload();
        });
        await host.reload();
        await entered.future;
        expect(observed, isEmpty);
        expect(remotes, isEmpty);
        final done = failure ? expectLater(fresh, throwsStateError) : fresh!;
        release.complete();
        await done;
        expect(observed, ['blocked']);
        expect(remotes, [false]);
        expectState(host, null, 'blocked', false);
        clean(host);
      },
    );
  }
}
