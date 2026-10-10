import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/safety_gate.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'actual registry clears three keys and never lifts killed gate',
    () async {
      SharedPreferences.setMockInitialValues({
        'safety.enabled': false,
        'safety.appAllowlist': 'notes',
        'safety.resumeAtMs': 123,
      });
      final gate = SafetyGate();
      gate.kill();
      final generation = gate.generation;
      await DataRegistry.stores.firstWhere((s) => s.id == 'safety').clear();
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        'safety.enabled',
        'safety.appAllowlist',
        'safety.resumeAtMs',
      ]) {
        expect(prefs.containsKey(key), isFalse);
      }
      expect(await gate.isEnabled(), isTrue);
      expect(await gate.allowlist(), isEmpty);
      expect(await gate.resumeAt(), isNull);
      expect(gate.killed, isTrue);
      expect(gate.generation, generation);
    },
  );
  for (final held in [
    'safety.resumeAtMs',
    'safety.enabled',
    'safety.appAllowlist',
  ]) {
    test(
      'entered $held write cannot undo completed clear, fresh choices work',
      () async {
        final stored = <String, Object?>{};
        final entered = Completer<void>(), release = Completer<void>();
        var first = true;
        final owner = SafetyPreferences.forTest(
          read: () async => Map.of(stored),
          write: (key, value) async {
            if (key == held && first) {
              first = false;
              entered.complete();
              await release.future;
            }
            stored[key] = value;
            return true;
          },
          remove: (key) async {
            stored.remove(key);
            return true;
          },
        );
        final gate = SafetyGate(preferences: owner);
        final old = held == 'safety.appAllowlist'
            ? gate.setAllowlist({'old'})
            : gate.pauseFor(const Duration(minutes: 15));
        await entered.future;
        final clear = owner.clear();
        release.complete();
        await Future.wait([old, clear]);
        expect(stored, isEmpty);
        expect(await gate.isEnabled(), isTrue);
        await gate.pauseFor(const Duration(minutes: 1));
        await gate.setAllowlist({'new'});
        expect(await gate.isEnabled(), isFalse);
        expect(await gate.allowlist(), {'new'});
        expect(await gate.resumeAt(), isNotNull);
      },
    );
  }
  for (final op in ['write', 'remove']) {
    for (final throws in [false, true]) {
      test(
        '$op ${throws ? 'throw' : 'false'} is safe and queue retries',
        () async {
          final stored = <String, Object?>{
            'safety.enabled': true,
            'safety.appAllowlist': 'notes',
          };
          var fail = true;
          final owner = SafetyPreferences.forTest(
            read: () async => Map.of(stored),
            write: (key, value) async {
              if (op == 'write' && fail) {
                if (throws) throw StateError('private sentinel');
                return false;
              }
              stored[key] = value;
              return true;
            },
            remove: (key) async {
              if (op == 'remove' && fail) {
                if (throws) throw StateError('private sentinel');
                return false;
              }
              stored.remove(key);
              return true;
            },
          );
          final gate = SafetyGate(preferences: owner);
          await expectLater(
            op == 'write'
                ? gate.pauseFor(const Duration(minutes: 1))
                : owner.clear(),
            throwsA(
              isA<SafetyStorageException>().having(
                (e) => e.toString(),
                'safe',
                isNot(contains('private sentinel')),
              ),
            ),
          );
          expect(await gate.isEnabled(), isTrue);
          expect(stored['safety.appAllowlist'], 'notes');
          fail = false;
          await owner.clear();
          expect(stored, isEmpty);
          await gate.pauseFor(const Duration(minutes: 1));
          expect(await gate.isEnabled(), isFalse);
        },
      );
    }
  }
  test(
    'failed disable after written pause deadline is honest partial state',
    () async {
      final stored = <String, Object?>{};
      var fail = true;
      final owner = SafetyPreferences.forTest(
        read: () async => Map.of(stored),
        write: (key, value) async {
          if (key == 'safety.enabled' && fail) return false;
          stored[key] = value;
          return true;
        },
        remove: (key) async {
          stored.remove(key);
          return true;
        },
      );
      final gate = SafetyGate(preferences: owner);
      await expectLater(
        gate.pauseFor(const Duration(minutes: 1)),
        throwsA(isA<SafetyStorageException>()),
      );
      expect(stored['safety.resumeAtMs'], isA<int>());
      expect(await gate.isEnabled(), isTrue);
      fail = false;
      await owner.clear();
      expect(stored, isEmpty);
    },
  );
  test(
    'entered expiry read cannot overwrite fresh post-clear disabled choice',
    () async {
      final stored = <String, Object?>{
        'safety.enabled': false,
        'safety.resumeAtMs': 1,
      };
      final entered = Completer<void>(), release = Completer<void>();
      var first = true;
      final owner = SafetyPreferences.forTest(
        read: () async {
          final result = Map<String, Object?>.of(stored);
          if (first) {
            first = false;
            entered.complete();
            await release.future;
          }
          return result;
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
      final gate = SafetyGate(
        preferences: owner,
        clock: Clock.fixed(DateTime.fromMillisecondsSinceEpoch(100)),
      );
      final old = gate.isEnabled();
      await entered.future;
      final clear = owner.clear();
      final choice = gate.setEnabled(false);
      release.complete();
      await old;
      await clear;
      await choice;
      expect(stored, {'safety.enabled': false});
      expect(await gate.isEnabled(), isFalse);
    },
  );
  test(
    'entered expiry setter is ordered before clear and fresh choice',
    () async {
      final stored = <String, Object?>{
        'safety.enabled': false,
        'safety.resumeAtMs': 1,
      };
      final entered = Completer<void>(), release = Completer<void>();
      var first = true;
      final owner = SafetyPreferences.forTest(
        read: () async => Map.of(stored),
        write: (key, value) async {
          if (key == 'safety.enabled' && first) {
            first = false;
            entered.complete();
            await release.future;
          }
          stored[key] = value;
          return true;
        },
        remove: (key) async {
          stored.remove(key);
          return true;
        },
      );
      final gate = SafetyGate(
        preferences: owner,
        clock: Clock.fixed(DateTime.fromMillisecondsSinceEpoch(100)),
      );
      final old = gate.isEnabled();
      await entered.future;
      final clear = owner.clear();
      final choice = gate.setEnabled(false);
      release.complete();
      await old;
      await clear;
      await choice;
      expect(stored, {'safety.enabled': false});
    },
  );
  test('read failure never authorizes confirmation bypass', () async {
    final owner = SafetyPreferences.forTest(
      read: () async => throw StateError('private'),
      write: (key, value) async => true,
      remove: (key) async => true,
    );
    final gate = SafetyGate(preferences: owner, onConfirm: (_) async => true);
    await expectLater(
      gate.authorize('click', {}),
      throwsA(isA<SafetyStorageException>()),
    );
  });
  test('entered removal completes before a fresh post-clear pause', () async {
    final stored = <String, Object?>{
      'safety.enabled': false,
      'safety.appAllowlist': 'old',
      'safety.resumeAtMs': 2,
    };
    final entered = Completer<void>(), release = Completer<void>();
    var first = true;
    final owner = SafetyPreferences.forTest(
      read: () async => Map.of(stored),
      write: (key, value) async {
        stored[key] = value;
        return true;
      },
      remove: (key) async {
        if (first) {
          first = false;
          entered.complete();
          await release.future;
        }
        stored.remove(key);
        return true;
      },
    );
    final clear = owner.clear();
    await entered.future;
    final choice = SafetyGate(preferences: owner)
        .pauseFor(const Duration(minutes: 1));
    release.complete();
    await clear;
    await choice;
    expect(stored['safety.enabled'], isFalse);
    expect(stored['safety.resumeAtMs'], isA<int>());
    expect(stored.containsKey('safety.appAllowlist'), isFalse);
  });
  test(
    'stale disabled read after explicit enable cannot bypass confirmations',
    () async {
      final stored = <String, Object?>{'safety.enabled': false};
      final entered = Completer<void>(), release = Completer<void>();
      var first = true;
      final owner = SafetyPreferences.forTest(
        read: () async {
          final result = Map<String, Object?>.of(stored);
          if (first) {
            first = false;
            entered.complete();
            await release.future;
          }
          return result;
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
      final gate = SafetyGate(preferences: owner);
      final auth = gate.authorize('click', {});
      await entered.future;
      final enable = gate.setEnabled(true);
      release.complete();
      expect(await auth, isFalse);
      await enable;
    },
  );
  test(
    'partial clear failure retains actual remainder and retry removes it',
    () async {
      final stored = <String, Object?>{
        'safety.enabled': false,
        'safety.appAllowlist': 'notes',
        'safety.resumeAtMs': 1,
      };
      var fail = true;
      final owner = SafetyPreferences.forTest(
        read: () async => Map.of(stored),
        write: (key, value) async {
          stored[key] = value;
          return true;
        },
        remove: (key) async {
          if (key == 'safety.appAllowlist' && fail) return false;
          stored.remove(key);
          return true;
        },
      );
      final gate = SafetyGate(preferences: owner);
      gate.kill();
      await expectLater(
        gate.clearPreferences(),
        throwsA(isA<SafetyStorageException>()),
      );
      expect(stored, {'safety.appAllowlist': 'notes', 'safety.resumeAtMs': 1});
      expect(await gate.isEnabled(), isTrue);
      expect(gate.killed, isTrue);
      fail = false;
      await gate.clearPreferences();
      expect(stored, isEmpty);
      expect(gate.killed, isTrue);
    },
  );
}
