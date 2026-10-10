import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/watch_policy.dart';

class Policy {
  bool local = true;
  List<String> apps = ['notes'], deny = [];
  Completer<void>? blocked;
  final entered = Completer<void>();
  late final watch = ScreenWatch.forTesting(
    clock: Clock.fixed(DateTime(2026, 10, 10)),
    localOnly: () async => local,
    allowlist: () async {
      if (!entered.isCompleted) entered.complete();
      await blocked?.future;
      return List.of(apps);
    },
    denylist: () async => List.of(deny),
  );
  Future<void> start() async {
    final consent = await watch.prepareConsent();
    expect(await watch.start(consentConfirmed: true, consent: consent), isNull);
  }
}

void main() {
  test(
    'consent snapshot immutable and scope/length changes require new dialog',
    () async {
      final p = Policy();
      final consent = await p.watch.prepareConsent();
      expect(() => consent.apps.add('mail'), throwsUnsupportedError);
      p.apps.add('mail');
      expect(
        await p.watch.start(consentConfirmed: true, consent: consent),
        contains('scope changed'),
      );
      p.apps.remove('mail');
      expect(
        await p.watch.start(
          consentConfirmed: true,
          consent: consent,
          length: const Duration(minutes: 15),
        ),
        contains('scope changed'),
      );
      expect(p.watch.isActive, isFalse);
      p.watch.dispose();
    },
  );
  test(
    'active/concurrent starts refused without extending consented duration',
    () async {
      final p = Policy()..blocked = Completer<void>();
      final first = p.watch.start(consentConfirmed: true);
      await p.entered.future;
      expect(await p.watch.start(consentConfirmed: true), contains('already'));
      p.blocked!.complete();
      expect(await first, isNull);
      final remaining = p.watch.remaining;
      expect(
        await p.watch.start(
          consentConfirmed: true,
          length: const Duration(minutes: 60),
        ),
        contains('already'),
      );
      expect(p.watch.remaining, remaining);
      p.watch.dispose();
    },
  );
  test(
    'stop during entered start cancels it and permits fresh session',
    () async {
      final p = Policy()..blocked = Completer<void>();
      final pending = p.watch.start(consentConfirmed: true);
      await p.entered.future;
      p.watch.stop();
      p.blocked!.complete();
      expect(await pending, contains('cancelled'));
      expect(p.watch.isActive, isFalse);
      p.blocked = null;
      await p.start();
      p.watch.dispose();
    },
  );
  test('new allowlisted app never broadens active session; fresh consent includes it', () async {
    final p = Policy();
    await p.start();
    p.apps.add('mail');
    expect(
      await p.watch.mayObserve(frontApp: 'Mail.app'),
      WatchVerdict.notAllowlisted,
    );
    expect(await p.watch.mayObserve(frontApp: 'Notes'), WatchVerdict.allow);
    p.watch.stop();
    await p.start();
    expect(await p.watch.mayObserve(frontApp: 'Mail'), WatchVerdict.allow);
    p.watch.dispose();
  });
  for (final restriction in ['local', 'remove', 'deny']) {
    test(
      '$restriction restriction stops session and drops entered observation result',
      () async {
        final p = Policy();
        await p.start();
        final entered = Completer<void>(), done = Completer<String>();
        var cancelled = 0, changes = 0;
        p.watch.registerInFlight(() {
          cancelled++;
        });
        p.watch.addListener(() {
          changes++;
        });
        final pending = p.watch.runIfAllowed(
          frontApp: 'Notes',
          operation: () {
            entered.complete();
            return done.future;
          },
        );
        await entered.future;
        if (restriction == 'local') p.local = false;
        if (restriction == 'remove') p.apps.clear();
        if (restriction == 'deny') p.deny.add('Notes.app');
        done.complete('private result');
        expect(await pending, isNull);
        expect(p.watch.isActive, isFalse);
        expect(cancelled, 1);
        expect(changes, 1);
        p.watch.dispose();
      },
    );
    test('$restriction gate refuses before operation begins', () async {
      final p = Policy();
      await p.start();
      if (restriction == 'local') p.local = false;
      if (restriction == 'remove') p.apps.clear();
      if (restriction == 'deny') p.deny.add('notes');
      var called = false;
      expect(
        await p.watch.runIfAllowed(
          frontApp: 'Notes',
          operation: () async {
            called = true;
            return 'x';
          },
        ),
        isNull,
      );
      expect(called, isFalse);
      expect(p.watch.isActive, isFalse);
      p.watch.dispose();
    });
  }
  test('stop/restart during entered gate cannot use a newer session', () async {
    final p = Policy();
    await p.start();
    p.blocked = Completer<void>();
    final pending = p.watch.runIfAllowed(
      frontApp: 'Notes',
      operation: () async => 'bad',
    );
    await Future<void>.delayed(Duration.zero);
    p.watch.stop();
    final old = p.blocked!;
    p.blocked = null;
    await p.start();
    old.complete();
    expect(await pending, isNull);
    p.watch.dispose();
  });
  test(
    'hard denies, private windows and lock remain stronger than snapshot',
    () async {
      final p = Policy()..apps = ['notes', '1password', 'safari'];
      await p.start();
      expect(
        await p.watch.mayObserve(frontApp: '1Password'),
        WatchVerdict.hardDenied,
      );
      expect(
        await p.watch.mayObserve(
          frontApp: 'Safari',
          windowTitle: 'Private Window',
        ),
        WatchVerdict.privateWindow,
      );
      expect(
        await p.watch.mayObserve(frontApp: 'Notes', locked: true),
        WatchVerdict.locked,
      );
      p.watch.dispose();
    },
  );
}
