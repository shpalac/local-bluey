import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Uses the already-resolved preferences plugin interface for held actual I/O.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/permission_watchdog.dart';
import 'package:local_bluey/services/permission_observation.dart';

class Checker extends PermissionChecker {
  final grants = <String, bool>{};
  String? fail;
  Future<bool> Function(String)? probe;
  final calls = <String>[];
  Future<bool> read(String id) {
    calls.add(id);
    if (fail == id) return Future.error(StateError('private'));
    return probe?.call(id) ?? Future.value(grants[id] ?? false);
  }

  @override
  Future<bool> accessibility() => read('accessibility');
  @override
  Future<bool> screenRecording() => read('screen_recording');
  @override
  Future<bool> microphone() => read('microphone');
  @override
  Future<bool> localNetwork() => read('local_network');
}

class ReadFails extends InMemorySharedPreferencesStore {
  ReadFails() : super.empty();
  @override
  Future<Map<String, Object>> getAll() async => throw StateError('private');
}

class HeldWrites extends InMemorySharedPreferencesStore {
  HeldWrites() : super.empty();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    entered.complete();
    await release.future;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<PermissionWatchdog> owner(
    Checker checker, {
    bool baseline = true,
  }) async {
    SharedPreferences.setMockInitialValues(
      baseline
          ? {
              'watchdog.granted.accessibility': true,
              'watchdog.granted.microphone': true,
            }
          : {},
    );
    return PermissionWatchdog(
      checker: checker,
      prefsOverride: await SharedPreferences.getInstance(),
    );
  }

  test('actual watchdog recovery list and successful fresh grant replace only actual result', () async {
    final checker = Checker();
    final wd = await owner(checker);
    final c = PermissionObservation(watchdog: wd);
    addTearDown(c.dispose);
    expect(c.status, PermissionObservationStatus.unknown);
    expect(c.revoked, isEmpty);
    await c.check();
    expect(c.revoked.map((p) => p.id), ['accessibility', 'microphone']);
    expect(() => c.revoked.clear(), throwsUnsupportedError);
    checker.grants['accessibility'] = true;
    await c.check();
    expect(c.revoked.map((p) => p.id), ['microphone']);
    expect(c.status, PermissionObservationStatus.current);
  });
  for (final id in [
    'accessibility',
    'screen_recording',
    'microphone',
    'local_network',
  ]) {
    test(
      'actual checker $id failure retains list safely then explicit recovery',
      () async {
        final checker = Checker();
        final wd = await owner(checker);
        final c = PermissionObservation(watchdog: wd);
        addTearDown(c.dispose);
        await c.check();
        checker.fail = id;
        await c.resume();
        expect(c.status, PermissionObservationStatus.failed);
        expect(c.revoked.map((p) => p.id), ['accessibility', 'microphone']);
        checker.fail = null;
        checker.grants.addAll({'accessibility': true, 'microphone': true});
        await c.check();
        expect(c.status, PermissionObservationStatus.current);
        expect(c.revoked, isEmpty);
        expect(
          checker.calls.every(
            (id) => onboardingPermissions.any((p) => p.id == id),
          ),
          true,
        );
      },
    );
  }
  test('actual preference read failure is failed observation not fabricated empty current', () async {
    final platform = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = platform);
    SharedPreferencesStorePlatform.instance = ReadFails();
    final c = PermissionObservation(
      watchdog: PermissionWatchdog(checker: Checker()),
    );
    addTearDown(c.dispose);
    await c.check();
    expect(c.status, PermissionObservationStatus.failed);
    expect(c.revoked, isEmpty);
  });
  test(
    'completion joins actual entered baseline write not just checker result',
    () async {
      final platform = SharedPreferencesStorePlatform.instance;
      addTearDown(() => SharedPreferencesStorePlatform.instance = platform);
      final held = HeldWrites();
      SharedPreferencesStorePlatform.instance = held;
      final prefs = await SharedPreferences.getInstance();
      final checker = Checker()..grants['accessibility'] = true;
      final c = PermissionObservation(
        watchdog: PermissionWatchdog(checker: checker, prefsOverride: prefs),
      );
      addTearDown(c.dispose);
      final done = c.check();
      await held.entered.future;
      var settled = false;
      done.then((_) => settled = true);
      expect(identical(done, c.check()), true);
      expect(settled, false);
      expect(c.loading, true);
      held.release.complete();
      await done;
      expect(c.status, PermissionObservationStatus.current);
    },
  );
  test('held actual older error suppressed, resume burst joins sequential fresh result', () async {
    final checker = Checker(),
        entered = Completer<void>(),
        gate = Completer<bool>();
    var accessibility = 0;
    checker.probe = (id) {
      if (id == 'accessibility' && accessibility++ == 0) {
        entered.complete();
        return gate.future;
      }
      return Future.value(true);
    };
    final c = PermissionObservation(watchdog: await owner(checker));
    addTearDown(c.dispose);
    var publications = 0;
    c.addListener(() => publications++);
    final done = c.check();
    await entered.future;
    for (var i = 0; i < 20; i++) {
      expect(identical(done, c.resume()), true);
      expect(identical(done, c.check()), true);
    }
    gate.completeError(StateError('private'));
    await done;
    expect(accessibility, 2);
    expect(c.status, PermissionObservationStatus.current);
    expect(c.revoked, isEmpty);
    expect(publications, 2);
  });
  test('existing clearBaseline and caller selected-id dismissal prevent stale list resurrection', () async {
    final checker = Checker();
    final wd = await owner(checker);
    final c = PermissionObservation(watchdog: wd);
    addTearDown(c.dispose);
    await c.check();
    final entered = Completer<void>(), gate = Completer<bool>();
    checker.probe = (id) {
      if (id == 'accessibility') {
        entered.complete();
        return gate.future;
      }
      return Future.value(false);
    };
    final pending = c.check();
    await entered.future;
    final clearing = wd.clearBaseline('accessibility');
    c.dismiss('accessibility');
    expect(c.revoked.map((p) => p.id), ['microphone']);
    await clearing;
    gate.complete(false);
    await pending;
    expect(c.revoked.map((p) => p.id), ['microphone']);
    checker.probe = null;
    checker.grants['accessibility'] = true;
    await c.check();
    checker.grants['accessibility'] = false;
    await c.check();
    expect(c.revoked.map((p) => p.id), ['accessibility', 'microphone']);
  });
  test('caller also filters already-produced delayed list without rewriting owner semantics', () async {
    final wd = await owner(Checker());
    var delayed = false;
    final entered = Completer<void>(),
        gate = Completer<List<OnboardingPermission>>();
    final c = PermissionObservation(
      watchdog: wd,
      read: () {
        if (delayed) {
          entered.complete();
          return gate.future;
        }
        return wd.recheckRevoked();
      },
    );
    addTearDown(c.dispose);
    await c.check();
    delayed = true;
    final done = c.check();
    await entered.future;
    c.dismiss('accessibility');
    gate.complete([onboardingPermissions[0], onboardingPermissions[2]]);
    await done;
    expect(c.revoked.map((p) => p.id), ['microphone']);
  });
  test('sync error contained with retained list', () async {
    final wd = await owner(Checker());
    var fail = false;
    final c = PermissionObservation(
      watchdog: wd,
      read: () {
        if (fail) throw StateError('private');
        return wd.recheckRevoked();
      },
    );
    addTearDown(c.dispose);
    await c.check();
    fail = true;
    await c.check();
    expect(c.status, PermissionObservationStatus.failed);
    expect(c.revoked.length, 2);
  });
  test('pending notification reentrant retry joins and disposal prevents queued probe', () async {
    final checker = Checker();
    final c = PermissionObservation(watchdog: await owner(checker));
    Future<void>? joined;
    c.addListener(() {
      joined = c.check();
      c.dispose();
    });
    final done = c.check();
    expect(identical(done, joined), true);
    await done;
    expect(checker.calls, isEmpty);
    c.dispose();
    await c.resume();
  });
  for (final failure in [false, true]) {
    test(
      'entered disposal settles without late display or fresh successor $failure',
      () async {
        final checker = Checker(),
            entered = Completer<void>(),
            gate = Completer<bool>();
        checker.probe = (id) {
          if (id == 'accessibility') {
            entered.complete();
            return gate.future;
          }
          return Future.value(false);
        };
        final c = PermissionObservation(watchdog: await owner(checker));
        var publications = 0;
        c.addListener(() => publications++);
        final done = c.check();
        await entered.future;
        c.resume();
        c.dispose();
        if (failure) {
          gate.completeError(StateError('private'));
        } else {
          gate.complete(false);
        }
        await done;
        expect(publications, 1);
        expect(c.revoked, isEmpty);
        expect(checker.calls.where((id) => id == 'accessibility').length, 1);
      },
    );
  }
  test('terminal listener disposal is safe', () async {
    final c = PermissionObservation(watchdog: await owner(Checker()));
    c.addListener(() {
      if (!c.loading) c.dispose();
    });
    await c.check();
    c.dispose();
  });
  test(
    'source-only main retains watchdog and original selected-id effects',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('PermissionObservation(watchdog: _watchdog)'));
      expect(
        source,
        contains('_permissions.addListener(_onPermissionsChanged);'),
      );
      expect(source, contains('unawaited(_permissions.check());'));
      expect(source, contains('unawaited(_permissions.resume());'));
      expect(
        source,
        contains('_permissions.removeListener(_onPermissionsChanged);'),
      );
      expect(source, contains('_permissions.dispose();'));
      expect(
        source,
        contains(
          '_watchdog.clearBaseline(id);\n                    _permissions.dismiss(id);',
        ),
      );
      expect(source, contains('_watchdog.recordGranted();'));
      expect('PermissionObservationNotice('.allMatches(source).length, 2);
    },
  );
}
