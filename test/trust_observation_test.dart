import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/host_control.dart';
import 'package:local_bluey/services/trust_observation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local_bluey/control');
  for (final value in [true, false, null]) {
    test('actual MacHostControl channel maps $value without prompts', () async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            return value;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final host = HostControl.forPlatform(operatingSystem: 'macos');
      final c = TrustObservation(read: host.isTrusted);
      addTearDown(c.dispose);
      expect(c.status, TrustObservationStatus.unknown);
      await c.check();
      expect(
        c.status,
        value == true
            ? TrustObservationStatus.granted
            : TrustObservationStatus.denied,
      );
      expect(c.lastObservation, value == true);
      await c.resume();
      await c.check();
      expect(methods, ['isTrusted', 'isTrusted', 'isTrusted']);
    });
  }
  test('actual channel failure is safe unknown not denial', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'private'),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final c = TrustObservation(read: const MacHostControl().isTrusted);
    addTearDown(c.dispose);
    await c.check();
    expect(c.status, TrustObservationStatus.failed);
    expect(c.lastObservation, isNull);
  });
  for (final synchronous in [false, true]) {
    for (final prior in [true, false]) {
      test(
        'retains $prior honestly on ${synchronous ? 'sync' : 'async'} failure then explicit success',
        () async {
          var fail = false, calls = 0;
          final c = TrustObservation(
            read: () {
              calls++;
              if (fail) {
                if (synchronous) throw StateError('private');
                return Future.error(StateError('private'));
              }
              return Future.value(prior);
            },
          );
          addTearDown(c.dispose);
          await c.check();
          fail = true;
          await c.check();
          expect(c.status, TrustObservationStatus.failed);
          expect(c.lastObservation, prior);
          expect(calls, 2);
          fail = false;
          await c.check();
          expect(
            c.status,
            prior
                ? TrustObservationStatus.granted
                : TrustObservationStatus.denied,
          );
          expect(calls, 3);
        },
      );
    }
  }
  test('entered startup resume burst joins through one fresh successor and drops old failure', () async {
    final reads = <Completer<bool>>[],
        entries = <Completer<void>>[Completer(), Completer()];
    var calls = 0, publications = 0;
    final c = TrustObservation(
      read: () {
        final gate = Completer<bool>();
        reads.add(gate);
        entries[calls++].complete();
        return gate.future;
      },
    );
    addTearDown(c.dispose);
    c.addListener(() => publications++);
    final first = c.check();
    await entries[0].future;
    for (var i = 0; i < 20; i++) {
      expect(identical(first, c.resume()), isTrue);
      expect(identical(first, c.check()), isTrue);
    }
    var settled = false;
    first.then((_) => settled = true);
    reads[0].completeError(StateError('private'));
    await entries[1].future;
    expect(calls, 2);
    expect(c.loading, isTrue);
    expect(publications, 1);
    expect(settled, isFalse);
    reads[1].complete(true);
    await first;
    expect(c.status, TrustObservationStatus.granted);
    expect(publications, 2);
    expect(calls, 2);
  });
  test('queued resume joins fresh queued read; retry before pending notify joins same future', () async {
    var calls = 0;
    final c = TrustObservation(
      read: () async {
        calls++;
        return false;
      },
    );
    addTearDown(c.dispose);
    Future<void>? reentrant;
    c.addListener(() {
      if (c.loading) reentrant = c.check();
    });
    final first = c.check();
    expect(identical(first, reentrant), isTrue);
    expect(identical(first, c.resume()), isTrue);
    expect(calls, 0);
    await first;
    expect(calls, 1);
  });
  test(
    'resume during successor requests one further fresh entered-period read',
    () async {
      final entered = [Completer<void>(), Completer<void>(), Completer<void>()];
      final gates = [Completer<bool>(), Completer<bool>(), Completer<bool>()];
      var calls = 0;
      final c = TrustObservation(
        read: () {
          final i = calls++;
          entered[i].complete();
          return gates[i].future;
        },
      );
      addTearDown(c.dispose);
      final done = c.check();
      await entered[0].future;
      c.resume();
      gates[0].complete(false);
      await entered[1].future;
      for (var i = 0; i < 10; i++) {
        c.resume();
      }
      gates[1].complete(true);
      await entered[2].future;
      expect(c.lastObservation, isNull);
      gates[2].complete(false);
      await done;
      expect(calls, 3);
      expect(c.status, TrustObservationStatus.denied);
    },
  );
  test(
    'queued disposal from pending notification prevents source entry',
    () async {
      var calls = 0;
      final c = TrustObservation(
        read: () async {
          calls++;
          return true;
        },
      );
      c.addListener(c.dispose);
      await c.check();
      await c.resume();
      await c.check();
      c.dispose();
      expect(calls, 0);
    },
  );
  for (final error in [false, true]) {
    test(
      'entered disposal drops fresh successor and publication $error',
      () async {
        final entered = Completer<void>(), gate = Completer<bool>();
        var calls = 0, notifications = 0;
        final c = TrustObservation(
          read: () {
            calls++;
            entered.complete();
            return gate.future;
          },
        );
        c.addListener(() => notifications++);
        final done = c.check();
        await entered.future;
        c.resume();
        c.dispose();
        if (error) {
          gate.completeError(StateError('private'));
        } else {
          gate.complete(true);
        }
        await done;
        expect(calls, 1);
        expect(notifications, 1);
        expect(c.lastObservation, isNull);
      },
    );
  }
  test('terminal notification reentrant new read preserves installed pending ownership', () async {
    var calls = 0;
    final c = TrustObservation(read: () async => ++calls == 1);
    addTearDown(c.dispose);
    Future<void>? fresh;
    c.addListener(() {
      if (c.status == TrustObservationStatus.granted) fresh = c.check();
    });
    await c.check();
    await fresh;
    expect(calls, 2);
    expect(c.status, TrustObservationStatus.denied);
  });
  test('terminal notification can dispose safely', () async {
    final c = TrustObservation(read: () async => true);
    c.addListener(() {
      if (!c.loading) c.dispose();
    });
    await c.check();
    c.dispose();
  });
  test(
    'actual main uses same startup resume disposal and both notice branches',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('final _trust = TrustObservation();'));
      expect(source, contains('unawaited(_trust.check());'));
      expect(source, contains('unawaited(_trust.resume());'));
      expect(source, contains('_trust.dispose();'));
      expect('TrustObservationNotice('.allMatches(source).length, 2);
      expect(source, isNot(contains('_trusted')));
      expect(
        source,
        contains(
          'await host.askPermission();\n    await host.openAccessibilitySettings();',
        ),
      );
    },
  );
}
