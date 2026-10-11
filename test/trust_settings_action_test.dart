import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/host_control.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/trust_observation.dart';
import 'package:local_bluey/ui/trust_observation_notice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Strings.uiLanguage = UiLanguage.english);
  tearDown(() => Strings.uiLanguage = UiLanguage.system);
  Future<void> mount(
    WidgetTester t,
    TrustObservation c,
    Future<void> Function() action,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrustObservationNotice(caller: c, openSettings: action),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  VoidCallback tap(WidgetTester t, String text) =>
      t.widget<TextButton>(find.widgetWithText(TextButton, text)).onPressed!;
  for (final sync in [false, true]) {
    testWidgets(
      'generic ${sync ? 'sync' : 'async'} failure explicit retry success is not grant',
      (t) async {
        final c = TrustObservation(read: () async => false);
        addTearDown(c.dispose);
        await c.check();
        var count = 0;
        await mount(t, c, () {
          count++;
          if (count == 1) {
            if (sync) throw StateError('private detail');
            return Future.error(StateError('private detail'));
          }
          return Future.value();
        });
        final dispatch = tap(t, 'Open settings');
        dispatch();
        dispatch();
        expect(count, 0);
        await t.pumpAndSettle();
        expect(count, 1);
        expect(find.textContaining('private'), findsNothing);
        expect(find.textContaining('Could not open'), findsOneWidget);
        expect(c.status, TrustObservationStatus.denied);
        tap(t, 'Retry opening settings')();
        await t.pumpAndSettle();
        expect(count, 2);
        expect(find.textContaining('Could not open'), findsNothing);
        expect(c.status, TrustObservationStatus.denied);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'held reentrant duplicate and status transitions retain error only on denial',
    (t) async {
      var mode = 'denied', count = 0;
      final c = TrustObservation(
        read: () async {
          if (mode == 'error') throw StateError('private');
          return mode == 'granted';
        },
      );
      addTearDown(c.dispose);
      await c.check();
      final release = Completer<void>();
      late VoidCallback dispatch;
      await mount(t, c, () {
        count++;
        dispatch();
        return release.future;
      });
      dispatch = tap(t, 'Open settings');
      dispatch();
      dispatch();
      await t.pump();
      expect(count, 1);
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Opening...'))
            .onPressed,
        isNull,
      );
      for (final next in ['granted', 'error']) {
        mode = next;
        final done = c.check();
        await t.pump();
        await done;
        await t.pump();
        expect(find.text('Opening...'), findsNothing);
        expect(count, 1);
      }
      release.completeError(StateError('private'));
      await t.pumpAndSettle();
      expect(find.textContaining('Could not open'), findsNothing);
      mode = 'denied';
      await c.check();
      await t.pumpAndSettle();
      expect(find.textContaining('Could not open'), findsOneWidget);
      expect(count, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'queued status change prevents entry and old dispatch after teardown is inert',
    (t) async {
      var count = 0;
      final c = TrustObservation(read: () async => false);
      addTearDown(c.dispose);
      await c.check();
      await mount(t, c, () async {
        count++;
      });
      final dispatch = tap(t, 'Open settings');
      dispatch();
      final checked = c.check();
      await t.pumpAndSettle();
      await checked;
      expect(count, 0);
      await t.pumpWidget(const SizedBox.shrink());
      dispatch();
      await t.pump();
      expect(count, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('queued disposal prevents callback entry', (t) async {
    var count = 0;
    final c = TrustObservation(read: () async => false);
    addTearDown(c.dispose);
    await c.check();
    await mount(t, c, () async {
      count++;
    });
    final dispatch = tap(t, 'Open settings');
    // Dispatch while the replacement tree is building: finalization disposes
    // the old notice before the queued callback microtask can enter.
    await t.pumpWidget(
      Builder(
        builder: (_) {
          dispatch();
          return const SizedBox.shrink();
        },
      ),
    );
    await t.pumpAndSettle();
    expect(count, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('entered action error completes safely after teardown', (
    t,
  ) async {
    var count = 0;
    final c = TrustObservation(read: () async => false);
    addTearDown(c.dispose);
    await c.check();
    final release = Completer<void>();
    await mount(t, c, () {
      count++;
      return release.future;
    });
    tap(t, 'Open settings')();
    await t.pump();
    expect(count, 1);
    await t.pumpWidget(const SizedBox.shrink());
    release.completeError(StateError('private'));
    await t.pumpAndSettle();
    expect(count, 1);
    expect(t.takeException(), isNull);
  });
  for (final fail in ['none', 'askPermission', 'openAccessibilitySettings']) {
    testWidgets(
      'actual MacHostControl channel order $fail no grant inference',
      (t) async {
        const channel = MethodChannel('local_bluey/control');
        final calls = <String>[];
        final askRelease = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call.method);
              if (call.method == 'isTrusted') return false;
              if (call.method == 'askPermission') await askRelease.future;
              if (call.method == fail) throw PlatformException(code: 'private');
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final c = TrustObservation(read: const MacHostControl().isTrusted);
        addTearDown(c.dispose);
        await c.check();
        await mount(t, c, () async {
          const host = MacHostControl();
          await host.askPermission();
          await host.openAccessibilitySettings();
        });
        tap(t, 'Open settings')();
        await t.pump();
        expect(calls, ['isTrusted', 'askPermission']);
        askRelease.complete();
        await t.pumpAndSettle();
        expect(
          calls,
          fail == 'askPermission'
              ? ['isTrusted', 'askPermission']
              : ['isTrusted', 'askPermission', 'openAccessibilitySettings'],
        );
        expect(c.status, TrustObservationStatus.denied);
        expect(find.textContaining('private'), findsNothing);
        expect(
          find.textContaining('Could not open'),
          fail == 'none' ? findsNothing : findsOneWidget,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
