import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/permission_watchdog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Checker extends PermissionChecker {
  final grants = <String, bool>{'microphone': true};
  Completer<void>? entered;
  Completer<bool>? release;
  @override
  Future<bool> accessibility() async => false;
  @override
  Future<bool> screenRecording() async => false;
  @override
  Future<bool> localNetwork() async => false;
  @override
  Future<bool> microphone() {
    final r = release;
    if (r != null) {
      entered?.complete();
      return r.future;
    }
    return Future.value(grants['microphone'] ?? false);
  }
}

Future<void> _clearViaRegistry() => DataRegistry.stores
    .firstWhere((s) => s.id == 'permission_watchdog')
    .clear();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'watchdog.granted.microphone';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('registry clear during a held probe is not undone by it', () async {
    final checker = _Checker()
      ..entered = Completer<void>()
      ..release = Completer<bool>();
    final dog = PermissionWatchdog(checker: checker)..registerAsLive();
    addTearDown(dog.unregisterLive);
    expect(PermissionWatchdog.live, same(dog));
    final write = dog.recordGranted();
    await checker.entered!.future;
    final clear = _clearViaRegistry();
    checker.release!.complete(true);
    await write;
    await clear;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(key), isNull);
    // A fresh post-clear observation may establish a new baseline.
    checker.release = null;
    await dog.recordGranted();
    expect((await SharedPreferences.getInstance()).getBool(key), isTrue);
  });

  test('repeated clear and recheck after clear keep nothing old', () async {
    final checker = _Checker();
    final dog = PermissionWatchdog(checker: checker)..registerAsLive();
    addTearDown(dog.unregisterLive);
    await dog.recordGranted();
    await _clearViaRegistry();
    await _clearViaRegistry();
    expect((await SharedPreferences.getInstance()).getBool(key), isNull);
    checker.grants['microphone'] = false;
    expect(await dog.recheckRevoked(), isEmpty);
  });

  test('clear without a live owner still removes baselines', () async {
    SharedPreferences.setMockInitialValues({key: true, 'other': 1});
    expect(PermissionWatchdog.live, isNull);
    await _clearViaRegistry();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(key), isNull);
    expect(prefs.getInt('other'), 1);
  });

  test('a refused removal is reported and a fresh clear can retry', () async {
    _RefusingPrefs.refuse = true;
    SharedPreferences.setMockInitialValues({key: true});
    final real = await SharedPreferences.getInstance();
    final dog = PermissionWatchdog(
      checker: _Checker(),
      prefsOverride: _RefusingPrefs(real),
    )..registerAsLive();
    addTearDown(dog.unregisterLive);
    await expectLater(_clearViaRegistry(), throwsA(isA<StateError>()));
    expect(real.getBool(key), isTrue);
    _RefusingPrefs.refuse = false;
    await _clearViaRegistry();
    expect(real.getBool(key), isNull);
  });
}

class _RefusingPrefs implements SharedPreferences {
  _RefusingPrefs(this._p);
  final SharedPreferences _p;
  static bool refuse = true;
  @override
  Set<String> getKeys() => _p.getKeys();
  @override
  Future<bool> remove(String key) async => refuse ? false : _p.remove(key);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
