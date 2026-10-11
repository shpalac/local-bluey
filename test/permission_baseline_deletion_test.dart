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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _RefusingPrefs.mode = _Mode.none;
  });
  tearDown(() => PermissionWatchdog.debugClearStore = null);

  test('clear during a held probe is not undone by it', () async {
    final checker = _Checker()
      ..entered = Completer<void>()
      ..release = Completer<bool>();
    final dog = PermissionWatchdog(checker: checker);
    final write = dog.recordGranted();
    await checker.entered!.future;
    final clear = _clearViaRegistry();
    checker.release!.complete(true);
    await write;
    await clear;
    expect((await SharedPreferences.getInstance()).getBool(key), isNull);
    // A fresh post-clear observation may establish a new baseline.
    checker.release = null;
    await dog.recordGranted();
    expect((await SharedPreferences.getInstance()).getBool(key), isTrue);
  });

  test('retired and competing owners share one ordered write queue', () async {
    final heldChecker = _Checker()
      ..entered = Completer<void>()
      ..release = Completer<bool>();
    final retired = PermissionWatchdog(checker: heldChecker);
    final other = PermissionWatchdog(checker: _Checker());
    final first = retired.recordGranted(); // probe entered, then abandoned
    await heldChecker.entered!.future;
    final queued = other.recordGranted(); // probed before the clear
    await Future<void>.delayed(Duration.zero);
    final clear = _clearViaRegistry();
    heldChecker.release!.complete(true);
    await Future.wait([first, queued, clear]);
    expect((await SharedPreferences.getInstance()).getBool(key), isNull);
    // Both owners keep working for new observations after the clear.
    await other.recordGranted();
    expect((await SharedPreferences.getInstance()).getBool(key), isTrue);
  });

  test('a write already entered finishes before the removal runs', () async {
    final real = await SharedPreferences.getInstance();
    final gate = Completer<void>();
    final held = _HeldWritePrefs(real, gate);
    final dog = PermissionWatchdog(checker: _Checker(), prefsOverride: held);
    final write = dog.recordGranted();
    await held.entered.future;
    final clear = _clearViaRegistry();
    await Future<void>.delayed(Duration.zero);
    expect(real.getBool(key), isNull); // write still held, removal not run
    gate.complete();
    await write;
    await clear;
    expect(real.getBool(key), isNull);
  });

  test('repeated clear and recheck after clear keep nothing old', () async {
    final checker = _Checker();
    final dog = PermissionWatchdog(checker: checker);
    await dog.recordGranted();
    await _clearViaRegistry();
    await _clearViaRegistry();
    expect((await SharedPreferences.getInstance()).getBool(key), isNull);
    checker.grants['microphone'] = false;
    expect(await dog.recheckRevoked(), isEmpty);
  });

  test('clear removes only baseline keys', () async {
    SharedPreferences.setMockInitialValues({key: true, 'other': 1});
    await _clearViaRegistry();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(key), isNull);
    expect(prefs.getInt('other'), 1);
  });

  for (final mode in [_Mode.refuse, _Mode.thrown]) {
    test(
      '${mode.name} removal is reported, then a fresh clear retries',
      () async {
        SharedPreferences.setMockInitialValues({
          key: true,
          'watchdog.granted.accessibility': true,
        });
        final real = await SharedPreferences.getInstance();
        _RefusingPrefs.mode = mode;
        PermissionWatchdog.debugClearStore = _RefusingPrefs(real);
        await expectLater(_clearViaRegistry(), throwsA(isA<StateError>()));
        expect(real.getBool(key), isTrue); // partial/no deletion is not hidden
        _RefusingPrefs.mode = _Mode.none;
        await _clearViaRegistry();
        expect(real.getBool(key), isNull);
        expect(real.getBool('watchdog.granted.accessibility'), isNull);
      },
    );
  }
}

enum _Mode { none, refuse, thrown }

class _RefusingPrefs implements SharedPreferences {
  _RefusingPrefs(this._p);
  final SharedPreferences _p;
  static _Mode mode = _Mode.none;
  @override
  Set<String> getKeys() => _p.getKeys();
  @override
  Future<bool> remove(String key) async {
    if (mode == _Mode.thrown) throw StateError('/private/path');
    return mode == _Mode.refuse ? false : _p.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HeldWritePrefs implements SharedPreferences {
  _HeldWritePrefs(this._p, this._gate);
  final SharedPreferences _p;
  final Completer<void> _gate;
  final entered = Completer<void>();
  @override
  bool? getBool(String key) => _p.getBool(key);
  @override
  Future<bool> setBool(String key, bool value) async {
    if (!entered.isCompleted) entered.complete();
    await _gate.future;
    return _p.setBool(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
