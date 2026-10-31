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

  for (final held in ['icon', 'title', 'menu']) {
    test('pending $held requests join and disposal fences successor', () async {
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
    });
  }

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
}
