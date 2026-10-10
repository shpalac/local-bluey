import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/line_connection.dart';
import 'package:local_bluey/link/models.dart';

class FakeTransport implements LineTransport {
  FakeTransport() {
    controller = StreamController<List<int>>(
      onListen: () => listens++,
      onCancel: () {
        cancels++;
        return cancel?.call();
      },
    );
  }
  late StreamController<List<int>> controller;
  int listens = 0,
      cancels = 0,
      configured = 0,
      writes = 0,
      closes = 0,
      destroys = 0;
  Future<void> Function()? drain;
  Future<void> Function()? cancel;
  bool failWrite = false, failConfigure = false, failDestroy = false;
  @override
  Stream<List<int>> get input => controller.stream;
  @override
  void configure() {
    configured++;
    if (failConfigure) throw StateError("configure");
  }

  @override
  void write(String line) {
    writes++;
    if (failWrite) throw StateError("write");
  }

  @override
  Future<void> close() {
    closes++;
    return drain?.call() ?? Future.value();
  }

  @override
  void destroy() {
    destroys++;
    if (failDestroy) throw StateError("destroy");
  }
}

String wire(String command) => jsonEncode(Packet(command: command).toJson());
Future<List<Packet>> receive(List<List<int>> chunks, {int cap = 1024}) async {
  final t = FakeTransport(), received = <Packet>[];
  final c = LineConnection.withTransport(t, frameLimit: cap);
  c.packets.listen(received.add);
  c.start();
  for (final chunk in chunks) {
    t.controller.add(chunk);
  }
  await Future<void>.delayed(Duration.zero);
  await c.close();
  await t.controller.close();
  return received;
}

void main() {
  test('every byte split UTF8/Hebrew/newline delivers exact packets', () async {
    final bytes = utf8.encode('${wire('שלום')}\r\n${wire('next')}\n');
    for (var split = 1; split < bytes.length; split++) {
      expect(
        (await receive([bytes.sublist(0, split), bytes.sublist(split)]))
            .map((p) => p.command),
        ['שלום', 'next'],
      );
    }
    expect(
      (await receive(bytes.map((b) => [b]).toList())).map((p) => p.command),
      ['שלום', 'next'],
    );
  });
  test(
    'coalesced valid aggregate beyond cap retains all frames in order',
    () async {
      final frames = List.generate(25, (i) => wire('frame$i'));
      final cap = frames
          .map((s) => utf8.encode(s).length)
          .reduce((a, b) => a > b ? a : b);
      expect(
        (await receive([
          utf8.encode('${frames.join('\n')}\n'),
        ], cap: cap)).map((p) => p.command),
        List.generate(25, (i) => 'frame$i'),
      );
    },
  );
  test(
    'exact cap accepted, one over including unterminated tail closes once',
    () async {
      final text = wire('exact');
      final bytes = utf8.encode(text);
      expect(
        (await receive([
          utf8.encode('$text\n'),
        ], cap: bytes.length)).single.command,
        'exact',
      );
      for (final terminated in [false, true]) {
        final t = FakeTransport();
        final actual = LineConnection.withTransport(
          t,
          frameLimit: bytes.length,
        );
        var done = 0;
        final received = <Packet>[];
        actual.done.listen((_) => done++);
        actual.packets.listen(received.add);
        actual.start();
        t.controller.add(utf8.encode('$text ${terminated ? "\n" : ""}'));
        await Future<void>.delayed(Duration.zero);
        expect(actual.isClosed, isTrue);
        expect(done, 1);
        expect(received, isEmpty);
        expect(t.cancels, 1);
        await actual.close();
        await t.controller.close();
      }
    },
  );
  test(
    'malformed and invalid UTF8 ignored per line with valid recovery',
    () async {
      final result = await receive([
        [0xff, 10],
        utf8.encode('not json\n${wire('valid')}\n'),
      ]);
      expect(result.single.command, 'valid');
    },
  );
  for (final error in [false, true]) {
    test(
      'entered drain ${error ? "error" : "success"} logical done/tail/owned input immediately closed',
      () async {
        final t = FakeTransport(), release = Completer<void>();
        final entered = Completer<void>();
        t.drain = () {
          entered.complete();
          return release.future;
        };
        final c = LineConnection.withTransport(t);
        var done = 0;
        final packets = <Packet>[];
        c.done.listen((_) => done++);
        c.packets.listen(packets.add);
        c.start();
        t.controller.add(utf8.encode('{"pending":'));
        await Future<void>.delayed(Duration.zero);
        final a = c.close(), b = c.close();
        expect(identical(a, b), isTrue);
        await entered.future;
        expect(c.isClosed, isTrue);
        c.start();
        c.send(Packet(command: 'no'));
        await Future<void>.delayed(Duration.zero);
        var completed = false;
        unawaited(a.then((_) => completed = true));
        expect(completed, isFalse);
        expect(done, 1);
        expect(t.listens, 1);
        expect(t.configured, 1);
        expect(t.writes, 0);
        expect(t.cancels, 1);
        expect(t.closes, 1);
        expect(t.destroys, 0);
        t.controller.add(utf8.encode('${wire('after')}\n'));
        if (error) {
          release.completeError(StateError('late drain'));
        } else {
          release.complete();
        }
        await a;
        expect(t.destroys, 1);
        expect(packets, isEmpty);
        expect(done, 1);
        await t.controller.close();
      },
    );
  }
  test(
    'close before start never subscribes/writes; stream failure closes once',
    () async {
      final t = FakeTransport();
      final a = LineConnection.withTransport(t);
      await a.close();
      a.start();
      a.send(Packet(command: 'no'));
      expect(t.listens, 0);
      expect(t.writes, 0);
      unawaited(t.controller.close());
      final other = FakeTransport();
      final b = LineConnection.withTransport(other);
      var done = 0;
      b.done.listen((_) => done++);
      b.start();
      other.controller.addError(StateError('input'));
      await Future<void>.delayed(Duration.zero);
      expect(b.isClosed, isTrue);
      expect(done, 1);
      await b.close();
      await other.controller.close();
    },
  );
  for (final failure in ['cancel', 'configure', 'write', 'destroy', 'close']) {
    test('owned cleanup $failure failure isolated and done once', () async {
      final t = FakeTransport();
      if (failure == 'cancel') {
        t.cancel = () async => throw StateError('cancel');
      }
      if (failure == 'configure') t.failConfigure = true;
      if (failure == 'write') t.failWrite = true;
      if (failure == 'destroy') t.failDestroy = true;
      if (failure == 'close') t.drain = () => throw StateError('close');
      final c = LineConnection.withTransport(t);
      var done = 0;
      c.done.listen((_) => done++);
      c.start();
      if (failure == 'write') c.send(Packet(command: 'write'));
      await c.close();
      await Future<void>.delayed(Duration.zero);
      expect(done, 1);
      expect(t.closes, 1);
      expect(t.destroys, 1);
      expect(t.cancels, failure == 'configure' ? 0 : 1);
      unawaited(t.controller.close());
    });
  }
  for (final pending in ['drain', 'cancel']) {
    test('stalled $pending has finite fake-clock teardown and late error', () {
      fakeAsync((clock) {
        final t = FakeTransport(), release = Completer<void>();
        if (pending == 'drain') {
          t.drain = () => release.future;
        } else {
          t.cancel = () => release.future;
        }
        final c = LineConnection.withTransport(t);
        var done = 0, completed = false;
        c.done.listen((_) => done++);
        c.start();
        final a = c.close();
        expect(identical(a, c.close()), isTrue);
        unawaited(a.then((_) => completed = true));
        clock.flushMicrotasks();
        expect(c.isClosed, isTrue);
        expect(done, 1);
        expect(completed, isFalse);
        expect(t.destroys, 0);
        clock.elapse(const Duration(milliseconds: 1999));
        expect(completed, isFalse);
        clock.elapse(const Duration(milliseconds: 1));
        expect(completed, isTrue);
        expect(t.destroys, 1);
        expect(t.cancels, 1);
        release.completeError(StateError('late cleanup'));
        clock.flushMicrotasks();
        expect(done, 1);
        expect(t.destroys, 1);
      });
    });
  }
  test(
    'entered drain error force releases before deadline with fake clock',
    () {
      fakeAsync((clock) {
        final t = FakeTransport(), release = Completer<void>();
        t.drain = () => release.future;
        final c = LineConnection.withTransport(t);
        var completed = false;
        unawaited(c.close().then((_) => completed = true));
        clock.flushMicrotasks();
        expect(completed, isFalse);
        release.completeError(StateError('drain failed'));
        clock.flushMicrotasks();
        expect(completed, isTrue);
        expect(t.destroys, 1);
        expect(clock.elapsed, Duration.zero);
      });
    },
  );
  test('paused consumers do not block bounded transport teardown', () {
    fakeAsync((clock) {
      final t = FakeTransport();
      final actual = LineConnection.withTransport(t);
      final sub = actual.done.listen((_) {});
      sub.pause();
      var completed = false;
      unawaited(actual.close().then((_) => completed = true));
      clock.flushMicrotasks();
      expect(completed, isTrue);
      sub.resume();
      clock.flushMicrotasks();
    });
  });
}
