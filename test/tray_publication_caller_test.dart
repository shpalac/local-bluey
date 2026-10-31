import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/tray_publication_caller.dart';

void main() {
  TrayPublicationState state(bool active, [String title = '● 05:00']) =>
      TrayPublicationState(active: active, title: active ? title : '');

  test('native menu specification preserves order and kill switch', () {
    final inactive = TrayPublicationCaller.menuFor(false);
    final active = TrayPublicationCaller.menuFor(true);
    expect(
      inactive.where((entry) => !entry.isSeparator).map((entry) => entry.key),
      ['show', 'hide', 'ask', 'mute', 'status', 'stop', 'resume', 'quit'],
    );
    expect(
      active.where((entry) => !entry.isSeparator).map((entry) => entry.key),
      [
        'show',
        'hide',
        'ask',
        'mute',
        'status',
        'stopwatch',
        'stop',
        'resume',
        'quit',
      ],
    );
    expect(active.where((entry) => entry.isSeparator).length, 3);
    expect(inactive.where((entry) => entry.isSeparator).length, 3);
  });

  test('initial publication orders icon, title, menu exactly once', () async {
    final calls = <String>[];
    final caller = TrayPublicationCaller.operations(
      read: () => state(false),
      icon: () async => calls.add('icon'),
      title: (value) async => calls.add('title:$value'),
      menu: (active) async => calls.add('menu:$active'),
    );
    await caller.request();
    await caller.request();
    expect(calls, ['icon', 'title:', 'menu:false']);
    expect(caller.iconPublished, true);
    expect(caller.publishedTitle, '');
    expect(caller.publishedActive, false);
    expect(caller.failed, false);
    caller.dispose();
  });

  Future<void> verifyHeldRequest(String held) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final calls = <String>[];
    Future<void> operation(String step) async {
      calls.add(step);
      if (step == held) {
        entered.complete();
        await release.future;
      }
    }

    final caller = TrayPublicationCaller.operations(
      read: () => state(false),
      icon: () => operation('icon'),
      title: (_) => operation('title'),
      menu: (_) => operation('menu'),
    );
    final pending = caller.request();
    await entered.future;
    expect(identical(pending, caller.request()), true);
    caller.dispose();
    release.complete();
    await pending;
    expect(
      calls,
      [
        'icon',
        'title',
        'menu',
      ].take(['icon', 'title', 'menu'].indexOf(held) + 1),
    );
    await caller.request(explicitRetry: true);
    expect(caller.loading, false);
  }

  test('pending icon requests join and disposal fences successor', () async {
    await verifyHeldRequest('icon');
  });
  test('pending title requests join and disposal fences successor', () async {
    await verifyHeldRequest('title');
  });
  test('pending menu requests join and disposal fences successor', () async {
    await verifyHeldRequest('menu');
  });

  test('only active changes publish a new menu; title ticks do not', () async {
    var current = state(false);
    final calls = <String>[];
    final caller = TrayPublicationCaller.operations(
      read: () => current,
      icon: () async => calls.add('icon'),
      title: (title) async => calls.add('title:$title'),
      menu: (active) async => calls.add('menu:$active'),
    );
    await caller.request();
    current = state(true);
    await caller.request();
    current = state(true, '● 04:59');
    await caller.request();
    current = state(false);
    await caller.request();
    expect(calls.where((value) => value == 'icon').length, 1);
    expect(calls.where((value) => value.startsWith('menu:')), [
      'menu:false',
      'menu:true',
      'menu:false',
    ]);
    expect(caller.publishedTitle, '');
    caller.dispose();
  });

  test(
    'failed publication requires explicit retry for unchanged state',
    () async {
      var failing = true;
      var attempts = 0;
      final caller = TrayPublicationCaller.operations(
        read: () => state(true),
        icon: () async {},
        title: (_) async {},
        menu: (_) async {
          attempts++;
          if (failing) throw StateError('unavailable');
        },
      );
      await caller.request();
      expect(caller.failed, true);
      expect(caller.publishedActive, null);
      await caller.request();
      expect(attempts, 1);
      failing = false;
      await caller.request(explicitRetry: true);
      expect(attempts, 2);
      expect(caller.failed, false);
      expect(caller.publishedActive, true);
      caller.dispose();
    },
  );

  test(
    'reentrant requests converge on latest state before completion',
    () async {
      var current = state(false);
      final entered = Completer<void>();
      final release = Completer<void>();
      final menus = <bool>[];
      final caller = TrayPublicationCaller.operations(
        read: () => current,
        icon: () async {},
        title: (_) async {},
        menu: (active) async {
          menus.add(active);
          if (menus.length == 1) {
            entered.complete();
            await release.future;
          }
        },
      );
      final pending = caller.request();
      await entered.future;
      current = state(true);
      expect(identical(caller.request(), pending), true);
      release.complete();
      await pending;
      expect(menus, [false, true]);
      expect(caller.publishedActive, true);
      caller.dispose();
    },
  );
  test(
    'native operation failure preserves prior marker through unchanged ticks',
    () async {
      var current = state(false);
      var fail = false;
      var attempts = 0;
      final published = <bool>[];
      final caller = TrayPublicationCaller.operations(
        read: () => current,
        icon: () async {},
        title: (_) async {},
        menu: (active) async {
          attempts++;
          if (fail) throw StateError('native menu failed');
          published.add(active);
        },
      );
      await caller.request();
      expect(caller.publishedActive, false);
      current = state(true);
      fail = true;
      await caller.request();
      expect(caller.failed, true);
      expect(caller.publishedActive, false);
      final failedAttempts = attempts;
      current = state(true, '● 04:59');
      await caller.request();
      expect(attempts, failedAttempts);
      expect(caller.publishedActive, false);
      fail = false;
      await caller.request(explicitRetry: true);
      expect(caller.failed, false);
      expect(published, [false, true]);
      expect(caller.publishedActive, true);
      caller.dispose();
    },
  );

  Future<void> verifyNativeError(String step) async {
    var failing = true;
    final calls = <String>[];
    Future<void> operation(String name) async {
      calls.add(name);
      if (name == step && failing) throw StateError('private');
    }

    final caller = TrayPublicationCaller.operations(
      read: () => state(true),
      icon: () => operation('icon'),
      title: (_) => operation('title'),
      menu: (_) => operation('menu'),
    );
    await caller.request();
    expect(caller.failed, true);
    final before = calls.length;
    await caller.request();
    expect(calls.length, before);
    failing = false;
    await caller.request(explicitRetry: true);
    expect(caller.failed, false);
    expect(caller.publishedActive, true);
    expect(caller.publishedTitle, '● 05:00');
    caller.dispose();
  }

  Future<void> verifyNativeHeldSampling(String step) async {
    var current = state(false);
    final entered = Completer<void>();
    final release = Completer<void>();
    final calls = <String>[];
    var heldOnce = false;
    Future<void> operation(String name) async {
      calls.add(name);
      if (name == step && !heldOnce) {
        heldOnce = true;
        entered.complete();
        await release.future;
      }
    }

    final caller = TrayPublicationCaller.operations(
      read: () => current,
      icon: () => operation('icon'),
      title: (title) => operation('title:$title'.split(':').first),
      menu: (_) => operation('menu'),
    );
    final pending = caller.request();
    await entered.future;
    current = state(true, '● 03:02');
    expect(identical(pending, caller.request()), true);
    release.complete();
    await pending;
    expect(caller.publishedTitle, '● 03:02');
    expect(caller.publishedActive, true);
    expect(calls.where((value) => value == 'icon').length, 1);
    caller.dispose();
  }

  test('native icon error consumed and explicitly recovered', () async {
    await verifyNativeError('icon');
  });
  test('native title error consumed and explicitly recovered', () async {
    await verifyNativeError('title');
  });
  test('native menu error consumed and explicitly recovered', () async {
    await verifyNativeError('menu');
  });
  test('native icon samples latest state while operation is held', () async {
    await verifyNativeHeldSampling('icon');
  });
  test('native title samples latest state while operation is held', () async {
    await verifyNativeHeldSampling('title');
  });
  test('native menu samples latest state while operation is held', () async {
    await verifyNativeHeldSampling('menu');
  });

  test(
    'native icon asset failure rejects subsequent writes and supports retry',
    () async {
      var validAsset = false;
      final calls = <String>[];
      final caller = TrayPublicationCaller.operations(
        read: () => state(false),
        icon: () async {
          calls.add('asset');
          if (!validAsset) {
            throw StateError('native image decode returned null');
          }
        },
        title: (_) async => calls.add('title'),
        menu: (_) async => calls.add('menu'),
      );
      await caller.request();
      expect(caller.failed, true);
      expect(calls, ['asset']);
      await caller.request();
      expect(calls, ['asset']);
      validAsset = true;
      await caller.request(explicitRetry: true);
      expect(caller.failed, false);
      expect(calls, ['asset', 'asset', 'title', 'menu']);
      caller.dispose();
    },
  );

  test(
    'native menu reentrancy coalesces updates and keeps latest marker',
    () async {
      var current = state(false);
      final entered = Completer<void>();
      final released = Completer<void>();
      final menus = <bool>[];
      final caller = TrayPublicationCaller.operations(
        read: () => current,
        icon: () async {},
        title: (_) async {},
        menu: (active) async {
          menus.add(active);
          if (menus.length == 1) {
            entered.complete();
            await released.future;
          }
        },
      );
      final first = caller.request();
      await entered.future;
      current = state(true);
      for (var i = 0; i < 20; i++) {
        expect(identical(first, caller.request()), true);
      }
      released.complete();
      await first;
      expect(menus, [false, true]);
      expect(caller.publishedActive, true);
      caller.dispose();
    },
  );
}
