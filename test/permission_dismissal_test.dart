import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/permission_watchdog.dart';

class Checker extends PermissionChecker {
  final grants = <String, bool>{};
  String? hold;
  Completer<void>? entered;
  Completer<bool>? release;
  Future<bool> check(String id) {
    if (id == hold) {
      entered!.complete();
      return release!.future;
    }
    return Future.value(grants[id] ?? false);
  }

  @override
  Future<bool> accessibility() => check('accessibility');
  @override
  Future<bool> screenRecording() => check('screen_recording');
  @override
  Future<bool> microphone() => check('microphone');
  @override
  Future<bool> localNetwork() => check('local_network');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in ['record', 'recheck']) {
    for (final id in [
      'accessibility',
      'screen_recording',
      'microphone',
      'local_network',
    ]) {
      for (final granted in [false, true]) {
        test(
          'entered $mode/$id/$granted clear owns only dismissed id',
          () async {
            SharedPreferences.setMockInitialValues({
              'watchdog.granted.$id': true,
              'watchdog.granted.microphone': true,
            });
            final prefs = await SharedPreferences.getInstance(), c = Checker();
            c.grants.addAll({
              'accessibility': true,
              'screen_recording': true,
              'microphone': true,
              'local_network': true,
            });
            c.hold = id;
            c.entered = Completer<void>();
            c.release = Completer<bool>();
            final w = PermissionWatchdog(checker: c, prefsOverride: prefs);
            final pending = mode == 'record'
                ? w.recordGranted()
                : w.recheckRevoked();
            await c.entered!.future;
            await w.clearBaseline(id);
            await w.clearBaseline(id);
            c.release!.complete(granted);
            final result = await pending;
            expect(prefs.getBool('watchdog.granted.$id'), isNull);
            if (mode == 'recheck') {
              expect(
                (result as List<OnboardingPermission>).map((p) => p.id),
                isNot(contains(id)),
              );
            }
            final other = id == 'microphone' ? 'accessibility' : 'microphone';
            expect(prefs.getBool('watchdog.granted.$other'), isTrue);
            c.hold = null;
            c.grants[id] = true;
            await w.recordGranted();
            expect(prefs.getBool('watchdog.granted.$id'), isTrue);
            c.grants[id] = false;
            expect((await w.recheckRevoked()).map((p) => p.id), [id]);
          },
        );
      }
    }
  }
  test('dismissal during different entered checker invalidates whole original id observation', () async {
    SharedPreferences.setMockInitialValues({
      'watchdog.granted.accessibility': true,
      'watchdog.granted.local_network': true,
    });
    final prefs = await SharedPreferences.getInstance(), c = Checker();
    c.hold = 'local_network';
    c.entered = Completer<void>();
    c.release = Completer<bool>();
    final w = PermissionWatchdog(checker: c, prefsOverride: prefs);
    final pending = w.recheckRevoked();
    await c.entered!.future;
    await w.clearBaseline('accessibility');
    c.release!.complete(false);
    expect((await pending).map((p) => p.id), ['local_network']);
    expect(prefs.getBool('watchdog.granted.accessibility'), isNull);
  });
  test(
    'new invocation before clear future settles records fresh grant',
    () async {
      SharedPreferences.setMockInitialValues({
        'watchdog.granted.accessibility': true,
      });
      final prefs = await SharedPreferences.getInstance(), c = Checker();
      c.grants['accessibility'] = true;
      final w = PermissionWatchdog(checker: c, prefsOverride: prefs);
      final clear = w.clearBaseline('accessibility');
      final fresh = w.recordGranted();
      await clear;
      await fresh;
      expect(prefs.getBool('watchdog.granted.accessibility'), isTrue);
      c.grants['accessibility'] = false;
      expect((await w.recheckRevoked()).single.id, 'accessibility');
    },
  );
  test(
    'checker failure stays failure not denial, later dismissal and probe work',
    () async {
      SharedPreferences.setMockInitialValues({
        'watchdog.granted.accessibility': true,
      });
      final prefs = await SharedPreferences.getInstance(), c = Checker();
      c.hold = 'accessibility';
      c.entered = Completer<void>();
      c.release = Completer<bool>();
      final w = PermissionWatchdog(checker: c, prefsOverride: prefs);
      final pending = expectLater(w.recheckRevoked(), throwsStateError);
      await c.entered!.future;
      c.release!.completeError(StateError('fixture'));
      await pending;
      expect(prefs.getBool('watchdog.granted.accessibility'), isTrue);
      await w.clearBaseline('accessibility');
      c.hold = null;
      expect(await w.recheckRevoked(), isEmpty);
    },
  );
}
