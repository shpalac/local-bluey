import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/tray_publication_caller.dart';

class TrayChannel {
  final calls = <MethodCall>[];
  String? failing, heldStep;
  final entered = Completer<void>(), released = Completer<void>();
  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (call.method == heldStep) {
      if (!entered.isCompleted) entered.complete();
      await released.future;
    }
    if (call.method == failing) throw PlatformException(code: 'private');
    return null;
  }

  List<String> get methods => calls.map((c) => c.method).toList();
}

class _Listener with TrayListener {
  final clicked = <String?>[];
  @override
  void onTrayMenuItemClick(MenuItem menuItem) => clicked.add(menuItem.key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tray_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  void install(TrayChannel f) {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(channel, f.handle);
    // Actual setIcon still crosses its macOS rootBundle asset boundary.
    messenger.setMockMessageHandler(
      'flutter/assets',
      (message) async => ByteData.sublistView(Uint8List.fromList([1, 2, 3])),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMessageHandler('flutter/assets', null);
      debugDefaultTargetPlatformOverride = null;
      rootBundle.evict('assets/tray_icon.png');
    });
  }

  TrayPublicationState state(bool active, [String title = '● 05:00']) =>
      TrayPublicationState(active: active, title: active ? title : '');

  for (final step in ['setIcon', 'setTitle', 'setContextMenu']) {
    test('actual held $step installed join and successful markers', () async {
      final f = TrayChannel()..heldStep = step;
      install(f);
      final c = TrayPublicationCaller(read: () => state(false));
      final done = c.request();
      expect(c.loading, isTrue);
      expect(identical(done, c.request()), isTrue);
      var settled = false;
      done.then((_) => settled = true);
      await f.entered.future;
      expect(settled, isFalse);
      if (step == 'setIcon') expect(c.iconPublished, isFalse);
      if (step == 'setTitle') expect(c.publishedTitle, isNull);
      expect(c.publishedActive, isNull);
      expect(identical(done, c.request()), isTrue);
      f.released.complete();
      await done;
      expect(f.methods, ['setIcon', 'setTitle', 'setContextMenu']);
      expect(c.iconPublished, isTrue);
      expect(c.publishedTitle, '');
      expect(c.publishedActive, false);
      expect(c.visible, isFalse);
      expect(f.calls.first.arguments['base64Icon'], 'AQID');
      c.dispose();
    });
    test(
      'actual failure $step no unchanged-tick retry explicit fresh recovery',
      () async {
        final f = TrayChannel()..failing = step;
        install(f);
        var current = state(true);
        final c = TrayPublicationCaller(read: () => current);
        await c.request();
        expect(c.failed, isTrue);
        expect(c.publishedActive, isNull);
        final before = f.calls.length;
        current = state(true, '● 04:59');
        await c.request();
        await c.request();
        expect(f.calls.length, before);
        expect(c.failed, isTrue);
        f.failing = null;
        await c.request(explicitRetry: true);
        expect(c.failed, isFalse);
        expect(c.publishedTitle, '● 04:59');
        expect(c.publishedActive, true);
        c.dispose();
      },
    );
    test('actual held $step disposal fences later caller operations', () async {
      final f = TrayChannel()..heldStep = step;
      install(f);
      final c = TrayPublicationCaller(read: () => state(false));
      final done = c.request();
      await f.entered.future;
      c.dispose();
      c.dispose();
      f.released.complete();
      await done;
      final order = ['setIcon', 'setTitle', 'setContextMenu'];
      expect(f.methods, order.take(order.indexOf(step) + 1));
      final before = f.calls.length;
      await c.request(explicitRetry: true);
      expect(f.calls.length, before);
    });
  }
  for (final step in ['setIcon', 'setTitle', 'setContextMenu']) {
    test(
      'actual $step latest actual state sampled for next operation',
      () async {
        final f = TrayChannel()..heldStep = step;
        install(f);
        var current = state(false);
        final c = TrayPublicationCaller(read: () => current);
        final done = c.request();
        await f.entered.future;
        current = state(true, '● 03:02');
        for (var i = 0; i < 20; i++) {
          expect(identical(done, c.request()), isTrue);
        }
        f.released.complete();
        await done;
        expect(c.publishedTitle, '● 03:02');
        expect(c.publishedActive, true);
        final titles = f.calls
            .where((x) => x.method == 'setTitle')
            .map((x) => x.arguments['title'])
            .toList();
        expect(titles, step == 'setIcon' ? ['● 03:02'] : ['', '● 03:02']);
        final menus = f.calls
            .where((x) => x.method == 'setContextMenu')
            .toList();
        expect(menus.length, step == 'setContextMenu' ? 2 : 1);
        expect(f.methods.where((x) => x == 'setIcon').length, 1);
        c.dispose();
      },
    );
  }
  test('failed old menu drains latest active transition once', () async {
    final f = TrayChannel()
      ..heldStep = 'setContextMenu'
      ..failing = 'setContextMenu';
    install(f);
    var current = state(false);
    final c = TrayPublicationCaller(read: () => current);
    final done = c.request();
    await f.entered.future;
    current = state(true);
    c.request();
    f.released.complete();
    await done;
    expect(f.methods.where((m) => m == 'setContextMenu').length, 2);
    expect(c.failed, isTrue);
    expect(c.publishedActive, isNull);
    final n = f.calls.length;
    await c.request();
    expect(f.calls.length, n);
    f.failing = null;
    current = state(false);
    await c.request();
    expect(c.failed, isFalse);
    expect(c.publishedActive, false);
    c.dispose();
  });
  test(
    'actual ScreenWatch consent clock ticks title without menu churn',
    () async {
      final f = TrayChannel();
      install(f);
      var now = DateTime(2026, 1, 1);
      final watch = ScreenWatch.forTesting(
        clock: Clock(() => now),
        localOnly: () async => true,
        allowlist: () async => ['Editor'],
        denylist: () async => [],
      );
      final c = TrayPublicationCaller(
        read: () => TrayPublicationState.watch(watch),
      );
      await c.request();
      expect(await watch.start(consentConfirmed: false), isNotNull);
      expect(watch.isActive, isFalse);
      expect(await watch.start(consentConfirmed: true), isNull);
      await c.request();
      now = now.add(const Duration(seconds: 1));
      await c.request();
      expect(c.publishedTitle, '● 04:59');
      expect(f.methods.where((m) => m == 'setContextMenu').length, 2);
      expect(f.methods.where((m) => m == 'setIcon').length, 1);
      watch.stop();
      await c.request();
      expect(c.publishedTitle, '');
      expect(c.publishedActive, false);
      expect(f.methods.where((m) => m == 'setContextMenu').length, 3);
      c.dispose();
      watch.dispose();
    },
  );
  test('queued and reentrant disposal zero native entry', () async {
    final f = TrayChannel();
    install(f);
    final c = TrayPublicationCaller(read: () => state(false));
    Future<void>? joined;
    c.addListener(() {
      if (c.loading) {
        joined = c.request();
        c.dispose();
      }
    });
    final done = c.request();
    expect(identical(done, joined), isTrue);
    await done;
    expect(f.calls, isEmpty);
  });
  test('sync operation and read errors safely consumed', () async {
    for (final badRead in [false, true]) {
      final c = TrayPublicationCaller.operations(
        read: () {
          if (badRead) throw StateError('private');
          return state(false);
        },
        icon: () => throw StateError('private'),
        title: (_) async {},
        menu: (_) async {},
      );
      await c.request();
      expect(c.failed, isTrue);
      c.dispose();
    }
  });
  test(
    'actual entered mac asset may finish after disposal no next title/menu',
    () async {
      final f = TrayChannel();
      install(f);
      rootBundle.evict('assets/tray_icon.png');
      final entered = Completer<void>(), released = Completer<ByteData?>();
      messenger.setMockMessageHandler('flutter/assets', (data) {
        entered.complete();
        return released.future;
      });
      final c = TrayPublicationCaller(read: () => state(false));
      final done = c.request();
      await entered.future;
      c.dispose();
      released.complete(ByteData.sublistView(Uint8List.fromList([4])));
      await done;
      expect(f.methods, ['setIcon']);
      expect(c.iconPublished, isFalse);
    },
  );
  test('failed actual plugin menu maps proposed ids not prior ids', () async {
    final f = TrayChannel();
    install(f);
    final c = TrayPublicationCaller(read: () => state(false));
    await c.request();
    final old = f.calls.last.arguments['menu']['items'].firstWhere(
      (x) => x['key'] == 'show',
    )['id'];
    f.failing = 'setContextMenu';
    var current = state(true);
    final next = TrayPublicationCaller(read: () => current);
    await next.request();
    expect(next.failed, isTrue);
    expect(next.publishedActive, isNull);
    final proposed = f.calls.last.arguments['menu']['items'].firstWhere(
      (x) => x['key'] == 'show',
    )['id'];
    expect(old, isNot(proposed));
    final l = _Listener();
    trayManager.addListener(l);
    Future<void> click(int id) async {
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        'tray_manager',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onTrayMenuItemClick', {'id': id}),
        ),
        (_) => done.complete(),
      );
      await done.future;
    }

    await click(old);
    expect(l.clicked, isEmpty);
    await click(proposed);
    expect(l.clicked, ['show']);
    trayManager.removeListener(l);
    c.dispose();
    next.dispose();
  });
  test('actual asset rejection no channel write explicit retry', () async {
    final f = TrayChannel();
    install(f);
    rootBundle.evict('assets/tray_icon.png');
    messenger.setMockMessageHandler('flutter/assets', (_) async => null);
    final c = TrayPublicationCaller(read: () => state(false));
    await c.request();
    expect(c.failed, isTrue);
    expect(c.iconPublished, isFalse);
    expect(f.calls, isEmpty);
    await c.request();
    expect(f.calls, isEmpty);
    messenger.setMockMessageHandler(
      'flutter/assets',
      (_) async => ByteData.sublistView(Uint8List.fromList([1])),
    );
    rootBundle.evict('assets/tray_icon.png');
    await c.request(explicitRetry: true);
    expect(c.visible, isFalse);
    c.dispose();
  });
  test('actual active to stop during menu bounded fresh successor', () async {
    final f = TrayChannel()..heldStep = 'setContextMenu';
    install(f);
    var current = state(true);
    final c = TrayPublicationCaller(read: () => current);
    final done = c.request();
    await f.entered.future;
    current = state(false);
    c.request();
    f.released.complete();
    await done;
    expect(f.methods, [
      'setIcon',
      'setTitle',
      'setContextMenu',
      'setTitle',
      'setContextMenu',
    ]);
    expect(c.publishedActive, false);
    expect(c.publishedTitle, '');
    c.dispose();
  });
  test('reentrant before entry reads latest only, no self successor', () async {
    final f = TrayChannel();
    install(f);
    var current = state(false);
    final c = TrayPublicationCaller(read: () => current);
    Future<void>? joined;
    c.addListener(() {
      if (c.loading) {
        current = state(true);
        joined = c.request();
      }
    });
    final done = c.request();
    expect(identical(done, joined), isTrue);
    await done;
    expect(f.methods, ['setIcon', 'setTitle', 'setContextMenu']);
    expect(c.publishedActive, true);
    c.dispose();
  });
  test('failed transition preserves prior successful marker and menu error through ticks', () async {
    final f = TrayChannel();
    install(f);
    var current = state(false);
    final c = TrayPublicationCaller(read: () => current);
    await c.request();
    current = state(true);
    f.failing = 'setContextMenu';
    await c.request();
    expect(c.publishedActive, false);
    expect(c.failed, isTrue);
    final count = f.calls.length;
    current = state(true, '● 04:59');
    await c.request();
    expect(f.calls.length, count);
    expect(c.failed, isTrue);
    expect(c.publishedTitle, '● 05:00');
    current = state(false);
    await c.request();
    expect(c.failed, isTrue);
    expect(c.publishedActive, false);
    expect(f.methods.where((m) => m == 'setContextMenu').length, 3);
    f.failing = null;
    await c.request(explicitRetry: true);
    expect(c.failed, isFalse);
    expect(f.methods.where((m) => m == 'setContextMenu').length, 4);
    c.dispose();
  });
  test(
    'fresh successor bounded even with more requests during successor',
    () async {
      final first = Completer<void>(), second = Completer<void>();
      final releaseFirst = Completer<void>(), releaseSecond = Completer<void>();
      var current = state(false);
      var menus = 0;
      final titles = <String>[];
      final c = TrayPublicationCaller.operations(
        read: () => current,
        icon: () async {},
        title: (value) async {
          titles.add(value);
        },
        menu: (_) async {
          menus++;
          if (menus == 1) {
            first.complete();
            await releaseFirst.future;
          }
          if (menus == 2) {
            second.complete();
            await releaseSecond.future;
          }
        },
      );
      final done = c.request();
      await first.future;
      current = state(true);
      c.request();
      releaseFirst.complete();
      await second.future;
      current = state(false);
      for (var i = 0; i < 20; i++) {
        expect(identical(done, c.request()), isTrue);
      }
      releaseSecond.complete();
      await done;
      expect(menus, 2);
      expect(titles, ['', '● 05:00']);
      expect(c.desired!.active, false);
      expect(c.publishedActive, true);
      await c.request();
      expect(menus, 3);
      expect(c.publishedActive, false);
      c.dispose();
    },
  );
  test(
    'failed menu retried after returning to prior successful active state',
    () async {
      final f = TrayChannel();
      install(f);
      var current = state(false);
      final c = TrayPublicationCaller(read: () => current);
      await c.request();
      f.failing = 'setContextMenu';
      current = state(true);
      await c.request();
      expect(c.publishedActive, false);
      expect(c.failed, isTrue);
      final n = f.calls.length;
      current = state(false);
      f.failing = null;
      await c.request();
      expect(f.calls.skip(n).map((x) => x.method), [
        'setTitle',
        'setContextMenu',
      ]);
      expect(c.failed, isFalse);
      expect(c.publishedActive, false);
      c.dispose();
    },
  );
  test('main sole publication owner same actions both notices lifetime', () {
    final s = File('lib/main.dart').readAsStringSync();
    expect(s, contains('final _trayPublication = TrayPublicationCaller();'));
    expect(s, contains('unawaited(_trayPublication.request());'));
    expect(
      s,
      contains('Future<void> _syncWatchTray() => _trayPublication.request();'),
    );
    expect(
      'TrayPublicationNotice(caller: _trayPublication)'.allMatches(s).length,
      2,
    );
    final regions = s.split('MacNoticeRegion(').skip(1).toList();
    expect(regions.length, 2);
    for (final region in regions) {
      expect(
        'TrayPublicationNotice(caller: _trayPublication)'
            .allMatches(region)
            .length,
        1,
      );
    }
    expect(
      s.indexOf('_trayPublication.dispose();'),
      lessThan(s.indexOf('trayManager.removeListener(this);')),
    );
    expect(s, isNot(contains('trayManager.destroy')));
    expect(s, isNot(contains('_trayWatchActive')));
    expect(s, contains("case 'stopwatch':"));
    expect(s, contains('ScreenWatch.instance.stop();'));
  });
}
