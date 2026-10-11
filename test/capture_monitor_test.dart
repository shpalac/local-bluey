import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/watch_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'privacy.localOnly': true});
  });

  tearDown(() => PrivacyGuard.debugLocalOnlyOverride = null);

  Future<ScreenWatch> started() async {
    await WatchPolicy.addToAllowlist('Safari');
    final watch = ScreenWatch.forTesting();
    expect(await watch.start(consentConfirmed: true), isNull);
    addTearDown(watch.stop);
    return watch;
  }

  Future<String?> run(CaptureMonitor m, String app, {bool locked = false}) =>
      m.runIfAllowed<String>(
        frontApp: app,
        windowTitle: 'Some title',
        locked: locked,
        operation: () async => 'frame',
      );

  test('fresh state is off and cannot be resumed or paused into life', () {
    final watch = ScreenWatch.forTesting();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    expect(m.indicator, CaptureIndicator.off);
    expect(m.pause(), isFalse);
    expect(m.resume(), isFalse);
    expect(watch.isActive, isFalse);
    expect(m.indicator, CaptureIndicator.off);
  });

  test('indicator follows the session and pause never starts one', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    expect(m.indicator, CaptureIndicator.active);
    expect(m.pause(), isTrue);
    expect(m.indicator, CaptureIndicator.paused);
    expect(m.pause(), isFalse);
    expect(m.resume(), isTrue);
    expect(m.indicator, CaptureIndicator.active);
    m.stop();
    expect(m.indicator, CaptureIndicator.off);
    expect(m.resume(), isFalse);
    expect(watch.isActive, isFalse);
  });

  test('paused observation runs nothing and is counted', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    expect(await run(m, 'Safari'), 'frame');
    m.pause();
    expect(await run(m, 'Safari'), isNull);
    expect(m.refusals[CaptureRefusal.paused], 1);
    m.resume();
    expect(await run(m, 'Safari'), 'frame');
  });

  test('a pause does not survive the session ending', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    m.pause();
    watch.stop();
    expect(m.indicator, CaptureIndicator.off);
    await WatchPolicy.addToAllowlist('Safari');
    expect(await watch.start(consentConfirmed: true), isNull);
    addTearDown(watch.stop);
    expect(
      m.indicator,
      CaptureIndicator.active,
      reason: 'new session, no pause',
    );
    expect(m.paused, isFalse);
  });

  test('policy refusals are counted by reason, with no app names', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    expect(await run(m, '1Password'), isNull);
    expect(await run(m, 'Notes'), isNull);
    expect(await run(m, 'Safari', locked: true), isNull);
    expect(m.refusals[CaptureRefusal.hardDenied], 1);
    expect(m.refusals[CaptureRefusal.notAllowed], 1);
    expect(m.refusals[CaptureRefusal.locked], 1);
    expect(m.refusals[CaptureRefusal.privateWindow], 0);
    expect(m.refusals.toString(), isNot(contains('1Password')));
    m.resetRefusals();
    expect(m.refusals.values.every((v) => v == 0), isTrue);
  });

  test('stop is immediate and an in-flight result is discarded', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    final result = await m.runIfAllowed<String>(
      frontApp: 'Safari',
      operation: () async {
        m.stop();
        return 'late frame';
      },
    );
    expect(result, isNull);
    expect(watch.isActive, isFalse);
  });

  test('locking stops capture; an unlocked change does not', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    final lock = ValueNotifier<bool>(false);
    m.attachLock(lock, () => lock.value);
    lock.value = false;
    expect(watch.isActive, isTrue);
    lock.value = true;
    expect(watch.isActive, isFalse);
    expect(m.indicator, CaptureIndicator.off);
    expect(m.refusals[CaptureRefusal.locked], 1);
  });

  test(
    'attaching while already locked stops, and a throwing check fails closed',
    () async {
      final watch = await started();
      final m = CaptureMonitor(watch: watch);
      addTearDown(m.dispose);
      m.attachLock(ValueNotifier<bool>(true), () => throw StateError('boom'));
      expect(watch.isActive, isFalse);
    },
  );

  test('a fresh monitor after a restart starts off with zero counters', () {
    final m = CaptureMonitor(watch: ScreenWatch.forTesting());
    addTearDown(m.dispose);
    expect(m.indicator, CaptureIndicator.off);
    expect(m.refusals.values.every((v) => v == 0), isTrue);
  });

  test('the monitor notifies listeners on pause, resume and stop', () async {
    final watch = await started();
    final m = CaptureMonitor(watch: watch);
    addTearDown(m.dispose);
    var n = 0;
    m.addListener(() => n++);
    m.pause();
    m.resume();
    m.stop();
    expect(n, greaterThanOrEqualTo(2));
  });
}
