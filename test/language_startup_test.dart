import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/language_startup.dart';

void main() {
  test(
    'immediate scheduled disposal performs no mutation notification or entry',
    () async {
      var reads = 0, notices = 0;
      final c = LanguageStartup(
        reload: () async {
          reads++;
        },
      );
      c.addListener(() => notices++);
      final work = c.reload();
      c.dispose();
      c.dispose();
      await work;
      expect(c.loading, false);
      expect(c.failed, false);
      expect(notices, 0);
      expect(reads, 0);
      await c.retry();
      await c.reload();
      expect(reads, 0);
    },
  );
  for (final fail in [false, true]) {
    for (final disposeEntered in [false, true]) {
      test(
        'queued latest actual read fail=$fail disposed=$disposeEntered joins and settles',
        () async {
          var reads = 0, notices = 0, held = false;
          final entered = Completer<void>(), release = Completer<void>();
          Future<String?> read() async {
            reads++;
            if (held) {
              if (!entered.isCompleted) entered.complete();
              await release.future;
              if (fail) throw StateError('private');
            }
            return 'hebrew';
          }

          final owner = LanguagePreferences(read: (_) => read());
          await owner.load();
          final c = LanguageStartup(reload: owner.load);
          c.addListener(() => notices++);
          held = true;
          final beforeReads = reads;
          final obsolete = c.reload(), latest = c.reload(), retry = c.retry();
          expect(retry, same(latest));
          await entered.future;
          expect(notices, 1);
          expect(reads, beforeReads + 1);
          expect(c.loading, true);
          var settled = false;
          retry.then((_) => settled = true);
          await Future<void>.value();
          expect(settled, false);
          if (disposeEntered) c.dispose();
          final beforeNotices = notices;
          release.complete();
          await Future.wait([obsolete, latest, retry]);
          expect(settled, true);
          if (disposeEntered) {
            expect(notices, beforeNotices);
            expect(c.failed, false);
          } else {
            expect(c.loading, false);
            expect(c.failed, fail);
            expect(notices, 2);
          }
          expect(owner.uiLanguage, UiLanguage.hebrew);
          expect(owner.speechLanguage, 'hebrew');
          c.dispose();
          owner.dispose();
        },
      );
    }
  }

  for (final ui in UiLanguage.values) {
    for (final failureKey in ['ui.language', 'speech.language']) {
      test(
        'actual $ui retained first/second read failure $failureKey retries fresh',
        () async {
          var fail = false, reads = 0, storedUi = ui.name, speech = 'he';
          Completer<void>? entered, release;
          final owner = LanguagePreferences(
            read: (key) async {
              reads++;
              if (key == failureKey &&
                  entered != null &&
                  !entered.isCompleted) {
                entered.complete();
                await release!.future;
              }
              if (fail && key == failureKey) throw StateError('private');
              return key == 'ui.language' ? storedUi : speech;
            },
            write: (_, _) async => throw StateError('no writes'),
            remove: (_) async => throw StateError('no reset'),
          );
          final old = Strings.debugOverride;
          Strings.debugOverride = owner;
          addTearDown(() {
            Strings.debugOverride = old;
            owner.dispose();
          });
          await Strings.load();
          final c = LanguageStartup();
          addTearDown(c.dispose);
          fail = true;
          entered = Completer<void>();
          release = Completer<void>();
          final loading = c.reload();
          await entered.future;
          expect(c.loading, true);
          expect(c.retry(), same(loading));
          release.complete();
          await loading;
          expect(c.failed, true);
          expect(Strings.uiLanguage, ui);
          expect(Strings.speechLanguage, 'he');
          final before = reads;
          fail = false;
          storedUi = 'hebrew';
          speech = 'en';
          await c.retry();
          expect(reads, before + 2);
          expect(c.failed, false);
          expect(Strings.uiLanguage, UiLanguage.hebrew);
          expect(Strings.speechLanguage, 'en');
          expect(Strings.forceRtl, true);
        },
      );
    }
  }
  test(
    'actual reconciliation can publish choices while caller still failed',
    () async {
      var reads = 0;
      final owner = LanguagePreferences(
        read: (key) async {
          if (++reads == 1) throw StateError('private');
          return key == 'ui.language' ? 'hebrew' : 'he';
        },
      );
      final c = LanguageStartup(reload: owner.load);
      await c.reload();
      expect(c.failed, true);
      expect(owner.uiLanguage, UiLanguage.hebrew);
      await c.retry();
      expect(c.failed, false);
      c.dispose();
      owner.dispose();
    },
  );
  for (final disposed in [false, true]) {
    test(
      'actual entered stale failure disposed=$disposed never replaces latest state',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        var reads = 0;
        final owner = LanguagePreferences(
          read: (key) async {
            if (++reads == 1) {
              entered.complete();
              await release.future;
              throw StateError('private');
            }
            return key == 'ui.language' ? 'english' : 'auto';
          },
        );
        final c = LanguageStartup(reload: owner.load);
        var notices = 0;
        c.addListener(() => notices++);
        final old = c.reload();
        await entered.future;
        final latest = disposed ? Future<void>.value() : c.reload();
        if (disposed) c.dispose();
        final before = notices;
        release.complete();
        await Future.wait([old, latest]);
        expect(c.failed, false);
        if (disposed) expect(notices, before);
        c.dispose();
        owner.dispose();
      },
    );
  }
  for (final sync in [false, true]) {
    test(
      'sync=$sync contained, reentrant retry joins installed future',
      () async {
        var calls = 0;
        Future<void>? joined;
        final c = LanguageStartup(
          reload: () {
            calls++;
            if (sync) throw StateError('private');
            return Future.error(StateError('private'));
          },
        );
        c.addListener(() {
          if (c.loading) joined = c.retry();
        });
        final op = c.reload();
        await op;
        expect(joined, same(op));
        expect(calls, 1);
        expect(c.failed, true);
        c.dispose();
      },
    );
  }
  test('reentrant disposal prevents entry; caller success does not read saved values', () async {
    var calls = 0;
    final c = LanguageStartup(
      reload: () async {
        calls++;
      },
    );
    c.addListener(c.dispose);
    await c.reload();
    expect(calls, 0);
    final ok = LanguageStartup(reload: () async {});
    await ok.reload();
    expect(ok.failed, false);
    ok.dispose();
  });
  test('main uses same language-only helper, security/order retained', () {
    final s = File('lib/main.dart').readAsStringSync();
    expect(s, contains('final language = LanguageStartup();'));
    expect(s, contains('await language.reload();'));
    expect(s, contains('language: language'));
    for (final load in [
      'EgressMonitor.instance.load()',
      'ActionLog.instance.load()',
      'RoutineStore.instance.load()',
      'BiometricLock.instance.load()',
      'windowManager.ensureInitialized()',
      'character.reload()',
      'appearance.reload()',
    ]) {
      expect(s, contains('await $load;'));
    }
    expect(
      s.indexOf('await language.reload();'),
      lessThan(s.indexOf('await EgressMonitor.instance.load();')),
    );
    expect(s, contains('Strings.preferences'));
  });
}
