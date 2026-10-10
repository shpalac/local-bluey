import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/data_registry.dart';

void main() {
  for (final stage in ['read', 'ui-write', 'speech-write', 'remove']) {
    test('entered $stage cannot restore deleted choices', () async {
      final stored = <String, String>{
        'ui.language': 'hebrew',
        'speech.language': 'he',
      };
      final entered = Completer<void>(), release = Completer<void>();
      var hold = true;
      Future<void> pause(String operation) async {
        if (hold && operation == stage) {
          hold = false;
          entered.complete();
          await release.future;
        }
      }

      final owner = LanguagePreferences(
        read: (key) async {
          final value = stored[key];
          await pause('read');
          return value;
        },
        write: (key, value) async {
          await pause(key == 'ui.language' ? 'ui-write' : 'speech-write');
          stored[key] = value;
          return true;
        },
        remove: (key) async {
          await pause('remove');
          stored.remove(key);
          return true;
        },
      );
      Strings.debugOverride = owner;
      addTearDown(() => Strings.debugOverride = null);
      final old = stage == 'read'
          ? Strings.load()
          : stage == 'ui-write'
          ? Strings.setUiLanguage(UiLanguage.hebrew)
          : stage == 'speech-write'
          ? Strings.setSpeechLanguage('he')
          : Strings.clear();
      await entered.future;
      final clear = DataRegistry.stores
          .firstWhere((s) => s.id == 'language')
          .clear();
      release.complete();
      await Future.wait([old, clear]);
      expect(stored, isEmpty);
      expect(Strings.uiLanguage, UiLanguage.system);
      expect(Strings.speechLanguage, 'auto');
      await Future.wait([
        Strings.setUiLanguage(UiLanguage.english),
        Strings.setSpeechLanguage('en'),
      ]);
      expect(stored, {'ui.language': 'english', 'speech.language': 'en'});
      expect(Strings.uiLanguage, UiLanguage.english);
      expect(Strings.speechLanguage, 'en');
    });
  }
  for (final operation in [
    'read',
    'ui-write',
    'speech-write',
    'first-remove',
    'second-remove',
  ]) {
    for (final throwing in [false, true]) {
      if (operation == 'read' && !throwing) continue;
      test(
        '$operation ${throwing ? 'throw' : 'false'} reconciles actual state and recovers',
        () async {
          final stored = <String, String>{
            'ui.language': 'hebrew',
            'speech.language': 'he',
          };
          var fail = false;
          bool result() {
            if (throwing) throw StateError('private sentinel');
            return false;
          }

          final c = LanguagePreferences(
            read: (key) async {
              if (fail && operation == 'read') result();
              return stored[key];
            },
            write: (key, value) async {
              if (fail &&
                  operation ==
                      (key == 'ui.language' ? 'ui-write' : 'speech-write')) {
                return result();
              }
              stored[key] = value;
              return true;
            },
            remove: (key) async {
              if (fail &&
                  operation ==
                      (key == 'ui.language'
                          ? 'first-remove'
                          : 'second-remove')) {
                return result();
              }
              stored.remove(key);
              return true;
            },
          );
          await c.load();
          fail = true;
          await expectLater(
            operation == 'read'
                ? c.load()
                : operation == 'ui-write'
                ? c.setUiLanguage(UiLanguage.english)
                : operation == 'speech-write'
                ? c.setSpeechLanguage('en')
                : c.clear(),
            throwsA(
              isA<LanguageStorageException>().having(
                (e) => e.toString(),
                'safe',
                isNot(contains('private sentinel')),
              ),
            ),
          );
          expect(
            c.uiLanguage,
            operation == 'second-remove'
                ? UiLanguage.system
                : UiLanguage.hebrew,
          );
          expect(c.speechLanguage, 'he');
          expect(
            stored['ui.language'],
            operation == 'second-remove' ? isNull : 'hebrew',
          );
          fail = false;
          await c.clear();
          expect(stored, isEmpty);
          await c.setUiLanguage(UiLanguage.english);
          await c.setSpeechLanguage('en');
          expect(c.uiLanguage, UiLanguage.english);
          expect(c.speechLanguage, 'en');
        },
      );
    }
  }
  test(
    'pending choices before clear are invalidated; later choices both persist',
    () async {
      final stored = <String, String>{};
      final entered = Completer<void>(), release = Completer<void>();
      var held = false;
      final c = LanguagePreferences(
        read: (key) async {
          if (!held) {
            held = true;
            entered.complete();
            await release.future;
          }
          return stored[key];
        },
        write: (key, value) async {
          stored[key] = value;
          return true;
        },
        remove: (key) async {
          stored.remove(key);
          return true;
        },
      );
      final load = c.load();
      await entered.future;
      final old = c.setUiLanguage(UiLanguage.hebrew);
      final clear = c.clear();
      final ui = c.setUiLanguage(UiLanguage.english),
          speech = c.setSpeechLanguage('en');
      release.complete();
      await Future.wait([load, old, clear, ui, speech]);
      expect(stored, {'ui.language': 'english', 'speech.language': 'en'});
      expect(c.uiLanguage, UiLanguage.english);
      expect(c.speechLanguage, 'en');
    },
  );
}
