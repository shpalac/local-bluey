import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/window_action_caller.dart';

class WindowChannel {
  final calls = <String>[];
  String? failing, heldStep;
  bool minimized = true;
  final entered = Completer<void>(), released = Completer<void>();
  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    if (call.method == heldStep) {
      if (!entered.isCompleted) {
        entered.complete();
      }
      await released.future;
    }
    if (call.method == failing) {
      throw PlatformException(code: 'private-detail');
    }
    return call.method == 'isMinimized' ? minimized : null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  void install(WindowChannel f) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, f.handle);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  for (final step in ['isMinimized', 'restore', 'show', 'focus', 'hide']) {
    test('actual plugin held $step joins completion', () async {
      final f = WindowChannel()..heldStep = step;
      install(f);
      final c = WindowActionCaller();
      final intent = step == 'hide' ? WindowIntent.hide : WindowIntent.show;
      final done = c.request(intent);
      expect(c.loading, isTrue);
      expect(identical(done, c.request(intent)), isTrue);
      var settled = false;
      done.then((_) => settled = true);
      await f.entered.future;
      expect(settled, isFalse);
      expect(identical(done, c.request(intent)), isTrue);
      f.released.complete();
      await done;
      expect(
        f.calls,
        step == 'hide' ? ['hide'] : ['isMinimized', 'restore', 'show', 'focus'],
      );
      expect(c.visible, isFalse);
      c.dispose();
    });
    test('actual plugin failure $step generic explicit retry', () async {
      final f = WindowChannel()..failing = step;
      install(f);
      final c = WindowActionCaller();
      final intent = step == 'hide' ? WindowIntent.hide : WindowIntent.show;
      await c.request(intent);
      expect(c.failed, intent);
      final order = ['isMinimized', 'restore', 'show', 'focus'];
      expect(
        f.calls,
        step == 'hide'
            ? ['hide']
            : order.take(order.indexOf(step) + 1).toList(),
      );
      f.failing = null;
      final before = f.calls.length;
      await Future<void>.value();
      expect(f.calls.length, before);
      await c.request(c.failed!);
      expect(c.visible, isFalse);
      c.dispose();
    });
  }
  test('nonminimized actual show omits restore', () async {
    final f = WindowChannel()..minimized = false;
    install(f);
    final c = WindowActionCaller();
    await c.request(WindowIntent.show);
    expect(f.calls, ['isMinimized', 'show', 'focus']);
    c.dispose();
  });
  for (final initial in WindowIntent.values) {
    for (final endSame in [false, true]) {
      test(
        'conflicting burst initial$initial latestSame$endSame bounded',
        () async {
          final f = WindowChannel()
            ..heldStep = initial == WindowIntent.show ? 'show' : 'hide';
          install(f);
          final c = WindowActionCaller();
          final done = c.request(initial);
          await f.entered.future;
          final other = initial == WindowIntent.show
              ? WindowIntent.hide
              : WindowIntent.show;
          expect(identical(done, c.request(other)), isTrue);
          expect(identical(done, c.request(initial)), isTrue);
          if (!endSame) c.request(other);
          f.released.complete();
          await done;
          final first = initial == WindowIntent.show
              ? ['isMinimized', 'restore', 'show', 'focus']
              : ['hide'];
          final second = other == WindowIntent.show
              ? ['isMinimized', 'restore', 'show', 'focus']
              : ['hide'];
          expect(f.calls, [...first, if (!endSame) ...second]);
          c.dispose();
        },
      );
    }
  }
  test('superseded error cannot overwrite successful latest intent', () async {
    final f = WindowChannel()
      ..heldStep = 'show'
      ..failing = 'show';
    install(f);
    final c = WindowActionCaller();
    final done = c.request(WindowIntent.show);
    await f.entered.future;
    c.request(WindowIntent.hide);
    f.released.complete();
    await done;
    expect(f.calls, ['isMinimized', 'restore', 'show', 'hide']);
    expect(c.failed, isNull);
    c.dispose();
  });
  test('final successor error names final intent only', () async {
    final f = WindowChannel()
      ..heldStep = 'show'
      ..failing = 'hide';
    install(f);
    final c = WindowActionCaller();
    final done = c.request(WindowIntent.show);
    await f.entered.future;
    c.request(WindowIntent.hide);
    f.released.complete();
    await done;
    expect(c.failed, WindowIntent.hide);
    c.dispose();
  });
  test(
    'reentrant pending explicit replacement before entry latest only',
    () async {
      final f = WindowChannel();
      install(f);
      final c = WindowActionCaller();
      Future<void>? joined;
      c.addListener(() {
        if (c.loading && joined == null) joined = c.request(WindowIntent.hide);
      });
      final done = c.request(WindowIntent.show);
      expect(identical(done, joined), isTrue);
      await done;
      expect(f.calls, ['hide']);
      c.dispose();
    },
  );
  test('joined completion includes held successor', () async {
    final first = Completer<void>(),
        second = Completer<void>(),
        entered = Completer<void>();
    final c = WindowActionCaller.operations(
      show: () => first.future,
      focus: () async {},
      hide: () {
        entered.complete();
        return second.future;
      },
    );
    final done = c.request(WindowIntent.show);
    await Future<void>.value();
    c.request(WindowIntent.hide);
    first.complete();
    await entered.future;
    var settled = false;
    done.then((_) => settled = true);
    await Future<void>.value();
    expect(settled, isFalse);
    second.complete();
    await done;
    expect(c.visible, isFalse);
    c.dispose();
  });
  test('sync injected throw contained', () async {
    final c = WindowActionCaller.operations(
      show: () => throw StateError('private'),
      focus: () async {},
      hide: () async {},
    );
    await c.request(WindowIntent.show);
    expect(c.failed, WindowIntent.show);
    c.dispose();
  });
  test('queued disposal prevents any actual plugin entry', () async {
    final f = WindowChannel();
    install(f);
    final c = WindowActionCaller();
    final done = c.request(WindowIntent.show);
    c.dispose();
    await done;
    await c.request(WindowIntent.hide);
    expect(f.calls, isEmpty);
  });
  for (final step in ['show', 'focus', 'hide']) {
    test(
      'entered $step disposal fences caller successor and late publish',
      () async {
        final f = WindowChannel()..heldStep = step;
        install(f);
        final c = WindowActionCaller();
        var notices = 0;
        c.addListener(() => notices++);
        final done = c.request(
          step == 'hide' ? WindowIntent.hide : WindowIntent.show,
        );
        await f.entered.future;
        c.request(step == 'hide' ? WindowIntent.show : WindowIntent.hide);
        c.dispose();
        f.released.complete();
        await done;
        expect(
          f.calls,
          step == 'hide'
              ? ['hide']
              : step == 'show'
              ? ['isMinimized', 'restore', 'show']
              : ['isMinimized', 'restore', 'show', 'focus'],
        );
        expect(notices, 1);
      },
    );
  }
  for (final step in ['isMinimized', 'restore']) {
    test(
      'entered actual show internal $step may finish after disposal caller fence only',
      () async {
        final f = WindowChannel()..heldStep = step;
        install(f);
        final c = WindowActionCaller();
        var notices = 0;
        c.addListener(() => notices++);
        final done = c.request(WindowIntent.show);
        await f.entered.future;
        c.request(WindowIntent.hide);
        c.dispose();
        f.released.complete();
        await done;
        expect(f.calls, ['isMinimized', 'restore', 'show']);
        expect(notices, 1);
        await c.request(WindowIntent.show);
        expect(f.calls, ['isMinimized', 'restore', 'show']);
      },
    );
  }
  test('reentrant pending latest intent and disposal safe', () async {
    final f = WindowChannel();
    install(f);
    final c = WindowActionCaller();
    Future<void>? joined;
    c.addListener(() {
      if (c.loading) {
        joined = c.request(WindowIntent.hide);
        c.dispose();
      }
    });
    final done = c.request(WindowIntent.show);
    expect(identical(done, joined), isTrue);
    await done;
    expect(f.calls, isEmpty);
  });
  test(
    'main actual same caller icon/show/hide both notices teardown source-only',
    () {
      final s = File('lib/main.dart').readAsStringSync();
      expect(
        'unawaited(_windowAction.request(WindowIntent.show));'
            .allMatches(s)
            .length,
        2,
      );
      expect(
        s,
        contains('unawaited(_windowAction.request(WindowIntent.hide));'),
      );
      expect('WindowActionNotice('.allMatches(s).length, 2);
      expect(
        s.indexOf('_windowAction.dispose();'),
        lessThan(s.indexOf('_speechMute.dispose();')),
      );
      expect(s, isNot(contains('windowManager.focus();')));
    },
  );
}
