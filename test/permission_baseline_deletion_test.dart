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

  /// Completes once a full probe round has returned (observable barrier).
  final probed = Completer<void>();
  @override
  Future<bool> accessibility() async => false;
  @override
  Future<bool> screenRecording() async => false;
  @override
  Future<bool> localNetwork() async {
    if (!probed.isCompleted) probed.complete();
    return false;
  }

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

/// Deterministic fixture: only the permission store stays registered so
/// DataRegistry.deleteAll runs without platform plugins.
void _isolateRegistry() {
  final all = List<DataStoreInfo>.of(DataRegistry.stores);
  final only = all.firstWhere((s) => s.id == 'permission_watchdog');
  DataRegistry.stores
    ..clear()
    ..add(only);
  addTearDown(() {
    DataRegistry.stores
      ..clear()
      ..addAll(all);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'watchdog.granted.microphone';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    final otherChecker = _Checker();
    final queued = PermissionWatchdog(checker: otherChecker)
        .recordGranted(); // probed before the clear
    await otherChecker.probed.future;
    final clear = _clearViaRegistry();
    heldChecker.release!.complete(true);
    await Future.wait([first, queued, clear]);
    expect((await SharedPreferences.getInstance()).getBool(key), isNull);
    // Both owners keep working for new observations after the clear.
    await other.recordGranted();
    expect((await SharedPreferences.getInstance()).getBool(key), isTrue);
  });

  test('a write already entered finishes before the removal runs', () async {
    _isolateRegistry();
    final real = await SharedPreferences.getInstance();
    final gate = Completer<void>();
    final held = _HeldWritePrefs(real, gate);
    final dog = PermissionWatchdog(checker: _Checker(), prefsOverride: held);
    final write = dog.recordGranted();
    await held.entered.future;
    // A second write is queued behind the entered, held one.
    final secondChecker = _Checker();
    final second = PermissionWatchdog(
      checker: secondChecker,
      prefsOverride: held,
    ).recordGranted();
    await secondChecker.probed.future;
    final clear = DataRegistry.deleteAll();
    expect(real.getBool(key), isNull); // write still held, removal not run
    expect(held.setCalls, 1); // the queued write has not entered
    gate.complete();
    await Future.wait([write, second, clear]);
    expect(real.getBool(key), isNull);
    expect(held.setCalls, 1); // the queued write was invalidated, never ran
  });

  test(
    'actual DataRegistry.deleteAll clears baselines and keeps working',
    () async {
      _isolateRegistry();
      SharedPreferences.setMockInitialValues({key: true, 'other': 1});
      await DataRegistry.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(key), isNull);
      expect(prefs.getInt('other'), isNull);
      final dog = PermissionWatchdog(checker: _Checker());
      await dog.recordGranted();
      expect((await SharedPreferences.getInstance()).getBool(key), isTrue);
    },
  );

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

  test(
    'partial false and thrown removal keep other keys, then retry',
    () async {
      const acc = 'watchdog.granted.accessibility';
      const scr = 'watchdog.granted.screen_recording';
      SharedPreferences.setMockInitialValues({key: true, acc: true, scr: true});
      final real = await SharedPreferences.getInstance();
      final store = _RefusingPrefs(real)
        ..modes = {acc: _Mode.refuse, scr: _Mode.thrown};
      PermissionWatchdog.debugClearStore = store;
      await expectLater(
        _clearViaRegistry(),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'message',
            isNot(contains('/private')),
          ),
        ),
      );
      expect(real.getBool(key), isNull); // other keys continued
      expect(real.getBool(acc), isTrue); // refused key is not hidden
      expect(real.getBool(scr), isTrue); // thrown key is not hidden
      store.modes = {};
      await _clearViaRegistry();
      expect(real.getBool(acc), isNull);
      expect(real.getBool(scr), isNull);
    },
  );
}

enum _Mode { none, refuse, thrown }

class _RefusingPrefs implements SharedPreferences {
  _RefusingPrefs(this._p);
  final SharedPreferences _p;
  Map<String, _Mode> modes = {};
  @override
  Set<String> getKeys() => _p.getKeys();
  @override
  Future<bool> remove(String key) async {
    final mode = modes[key] ?? _Mode.none;
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
  int setCalls = 0;
  @override
  bool? getBool(String key) => _p.getBool(key);
  @override
  Future<bool> setBool(String key, bool value) async {
    setCalls++;
    if (!entered.isCompleted) entered.complete();
    await _gate.future;
    return _p.setBool(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
