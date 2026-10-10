import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/tutorial.dart';

class Store implements TutorialDoneStore {
  bool done = false;
  int writes = 0, removes = 0;
  Future<void> Function()? write, remove;
  @override
  Future<void> markDone() async {
    writes++;
    await write?.call();
    done = true;
  }

  @override
  Future<void> clear() async {
    removes++;
    await remove?.call();
    done = false;
  }
}

void finalEvent(TutorialController c) {
  c.notifyAwake();
  c.notifyAnswer();
  c.notifyPointed();
}

void main() {
  for (final mode in ['skip', 'point', 'answer']) {
    for (final error in [false, true]) {
      test(
        'entered $mode write then reset ${error ? 'error' : 'success'} new run not hidden',
        () async {
          final store = Store(),
              entered = Completer<void>(),
              release = Completer<void>();
          store.write = () {
            entered.complete();
            return release.future;
          };
          final c = TutorialController(store: store);
          addTearDown(c.dispose);
          if (mode == 'answer') {
            c.configure(pointing: false);
            c.notifyAwake();
            c.notifyAnswer();
          } else if (mode == 'point') {
            finalEvent(c);
          } else {
            unawaited(c.skip());
          }
          final old = c.completion!;
          await entered.future;
          final reset = c.reset();
          expect(store.removes, 0); // removal waits entered write
          if (error) {
            release.completeError(StateError('private fixture'));
          } else {
            release.complete();
          }
          await old;
          await reset;
          expect(store.done, isFalse);
          expect(c.visible, isTrue);
          expect(c.step, TutorialStep.wake);
          expect(c.storageError, isNull);
          expect(store.writes, 1);
          expect(store.removes, 1);
          store.write = null;
          await c.skip();
          expect(store.done, isTrue);
          expect(c.visible, isFalse);
        },
      );
    }
  }
  for (final mode in ['skip', 'point', 'answer']) {
    test(
      'entered reset then $mode cannot complete new run before removal',
      () async {
        final store = Store()..done = true,
            entered = Completer<void>(),
            release = Completer<void>();
        store.remove = () {
          entered.complete();
          return release.future;
        };
        final c = TutorialController(store: store);
        addTearDown(c.dispose);
        final reset = c.reset();
        await entered.future;
        if (mode == 'answer') {
          c.configure(pointing: false);
          c.notifyAwake();
          c.notifyAnswer();
        } else if (mode == 'point') {
          finalEvent(c);
        } else {
          await c.skip();
        }
        expect(store.writes, 0);
        release.complete();
        await reset;
        expect(c.visible, isTrue);
        expect(c.step, TutorialStep.wake);
        expect(store.done, isFalse);
        store.remove = null;
        await c.skip();
        expect(store.done, isTrue);
      },
    );
  }
  for (final pointing in [false, true]) {
    test(
      'repeated terminal events/skip coalesce for pointing $pointing',
      () async {
        final store = Store(),
            entered = Completer<void>(),
            release = Completer<void>();
        store.write = () {
          entered.complete();
          return release.future;
        };
        final c = TutorialController(store: store);
        addTearDown(c.dispose);
        c.configure(pointing: pointing);
        if (pointing) {
          finalEvent(c);
          c.notifyPointed();
          c.notifyPointed();
        } else {
          c.notifyAwake();
          c.notifyAnswer();
          c.notifyAnswer();
        }
        final a = c.skip(), b = c.skip();
        expect(identical(a, b), isTrue);
        await entered.future;
        expect(store.writes, 1);
        expect(c.visible, isTrue);
        release.complete();
        await a;
        expect(c.visible, isFalse);
        expect(store.done, isTrue);
        await c.skip();
        expect(store.writes, 1);
      },
    );
  }
  test('void final event failure safe visible status no automatic retry and explicit success', () async {
    final store = Store(),
        entered = Completer<void>(),
        release = Completer<void>();
    store.write = () {
      entered.complete();
      return release.future;
    };
    final c = TutorialController(store: store);
    addTearDown(c.dispose);
    finalEvent(c);
    final checked = expectLater(
      c.completion!,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'safe',
          'Tutorial storage failed.',
        ),
      ),
    );
    await entered.future;
    release.completeError(StateError('private path'));
    await checked;
    expect(c.visible, isTrue);
    expect(store.done, isFalse);
    expect(c.storageError, 'Tutorial storage failed.');
    expect(store.writes, 1);
    store.write = null;
    await c.skip();
    expect(c.storageError, isNull);
    expect(c.visible, isFalse);
    expect(store.done, isTrue);
  });
  test(
    'reset remove failure truthful awaited safe and explicit recovery',
    () async {
      final store = Store();
      final c = TutorialController(store: store);
      addTearDown(c.dispose);
      await c.skip();
      store.remove = () async => throw StateError('private key');
      await expectLater(
        c.reset(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'safe',
            'Tutorial storage failed.',
          ),
        ),
      );
      expect(store.done, isTrue);
      expect(c.visible, isFalse);
      expect(c.storageError, 'Tutorial storage failed.');
      store.remove = null;
      await c.reset();
      expect(store.done, isFalse);
      expect(c.visible, isTrue);
      expect(c.storageError, isNull);
    },
  );
  test('awaited skip failure safe and explicit retry recovers queue', () async {
    final store = Store()..write = () async => throw StateError('private');
    final c = TutorialController(store: store);
    addTearDown(c.dispose);
    await expectLater(
      c.skip(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'safe',
          'Tutorial storage failed.',
        ),
      ),
    );
    expect(c.visible, isTrue);
    expect(store.done, isFalse);
    expect(c.storageError, 'Tutorial storage failed.');
    store.write = null;
    await c.skip();
    expect(store.done, isTrue);
    expect(c.storageError, isNull);
  });
  test(
    'entered reset invalidated by later reset publishes only newest run',
    () async {
      final store = Store()..done = true,
          entered = Completer<void>(),
          release = Completer<void>();
      store.remove = () {
        if (store.removes == 1) {
          entered.complete();
          return release.future;
        }
        return Future.value();
      };
      final c = TutorialController(store: store);
      addTearDown(c.dispose);
      c.dismiss();
      var publications = 0;
      c.addListener(() => publications++);
      final old = c.reset();
      await entered.future;
      final fresh = c.reset();
      release.complete();
      await old;
      await fresh;
      expect(publications, 1);
      expect(store.removes, 2);
      expect(store.done, isFalse);
      expect(c.visible, isTrue);
    },
  );
  test(
    'dispose during entered finish does not notify disposed listener',
    () async {
      final store = Store(),
          entered = Completer<void>(),
          release = Completer<void>();
      store.write = () {
        entered.complete();
        return release.future;
      };
      final c = TutorialController(store: store);
      var notifications = 0;
      c.addListener(() => notifications++);
      final pending = c.skip();
      await entered.future;
      c.dispose();
      release.complete();
      await pending;
      expect(notifications, 0);
    },
  );
}
