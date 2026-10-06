import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Future<ScreenWatch> startedWatch({Duration? length}) async {
    await WatchPolicy.addToAllowlist('Safari');
    final watch = ScreenWatch.forTesting();
    final refusal = await watch.start(
      length: length ?? const Duration(minutes: 5),
      consentConfirmed: true,
    );
    expect(refusal, isNull);
    return watch;
  }

  test('off by default - nothing may observe on a fresh launch', () async {
    final watch = ScreenWatch.forTesting();
    var called = 0;
    final result = await watch.runIfAllowed(
      frontApp: 'Safari',
      operation: () async {
        called++;
        return 'frame';
      },
    );
    expect(result, isNull);
    expect(called, 0);
    expect(watch.isActive, isFalse);
  });

  test('start refuses without consent, local-only, or an allowlist', () async {
    final watch = ScreenWatch.forTesting();
    expect(await watch.start(consentConfirmed: false), contains('go-ahead'));

    PrivacyGuard.debugLocalOnlyOverride = false;
    expect(await watch.start(consentConfirmed: true), contains('local-only'));
    PrivacyGuard.debugLocalOnlyOverride = true;

    expect(
      await watch.start(consentConfirmed: true),
      contains('at least one app'),
    );
  });

  test('allowlisted app observed only while the session is on', () async {
    final watch = await startedWatch();
    expect(await watch.mayObserve(frontApp: 'Safari'), WatchVerdict.allow);
    expect(
      await watch.mayObserve(frontApp: 'Xcode'),
      WatchVerdict.notAllowlisted,
    );
    watch.stop();
    expect(
      await watch.mayObserve(frontApp: 'Safari'),
      WatchVerdict.notAllowlisted,
    );
  });

  test('excluded app: nothing runs, only the counter moves', () async {
    final watch = await startedWatch();
    var called = 0;
    final result = await watch.runIfAllowed(
      frontApp: '1Password',
      operation: () async {
        called++;
        return 'frame';
      },
    );
    expect(result, isNull);
    expect(called, 0);
    expect(watch.excludedCount, 1);

    await watch.runIfAllowed(
      frontApp: 'Safari',
      windowTitle: 'New Incognito Tab',
      operation: () async => 'frame',
    );
    await watch.runIfAllowed(
      frontApp: 'Safari',
      locked: true,
      operation: () async => 'frame',
    );
    expect(watch.excludedCount, 3);

    // A merely unlisted app is not an "exclusion" and is not counted.
    await watch.runIfAllowed(frontApp: 'Xcode', operation: () async => 'frame');
    expect(watch.excludedCount, 3);
  });

  test('stop cancels in-flight work and drops its result', () async {
    final watch = await startedWatch();
    var cancelled = 0;
    void cancel() => cancelled++;
    watch.registerInFlight(cancel);

    final completer = Completer<String>();
    final pending = watch.runIfAllowed(
      frontApp: 'Safari',
      operation: () => completer.future,
    );

    watch.stop();
    expect(watch.isActive, isFalse);
    expect(cancelled, 1, reason: 'in-flight cancel fires synchronously');

    completer.complete('late frame');
    expect(await pending, isNull, reason: 'post-stop result is discarded');
  });

  test('session expires on its own after the fixed length', () {
    fakeAsync((zone) {
      // ignore: avoid_async_calls_in_sync_code - fakeAsync drives the clock.
      Zone.current.run(() async {
        final watch = await startedWatch(length: const Duration(minutes: 5));
        expect(watch.isActive, isTrue);
        expect(watch.remaining.inMinutes, 5);
        zone.elapse(const Duration(minutes: 4));
        expect(watch.isActive, isTrue);
        expect(watch.remaining.inMinutes, 1);
        zone.elapse(const Duration(minutes: 1, seconds: 1));
        expect(watch.isActive, isFalse);
      });
    });
  });

  test('a session never survives a restart - nothing is persisted', () async {
    final watch = await startedWatch();
    expect(watch.isActive, isTrue);
    final fresh = ScreenWatch.forTesting();
    expect(fresh.isActive, isFalse);
  });

  test('exclusion counter resets on demand', () async {
    final watch = await startedWatch();
    await watch.runIfAllowed(
      frontApp: '1Password',
      operation: () async => 'frame',
    );
    expect(watch.excludedCount, 1);
    watch.resetExcludedCount();
    expect(watch.excludedCount, 0);
  });
}
