import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bluey/services/speech.dart';
import 'package:local_bluey/services/speech_disposal_caller.dart';

import 'speech_playback_test.dart' show Clips, Player;

class Client extends http.BaseClient {
  int closes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();
  @override
  void close() {
    closes++;
  }
}

class HeldClips extends Clips {
  Completer<void>? deleting;
  final deletingEntered = Completer<void>();
  int deletes = 0;
  @override
  Future<void> delete(String path) async {
    deletes++;
    if (!deletingEntered.isCompleted) deletingEntered.complete();
    await deleting?.future;
    await super.delete(path);
  }
}

class HeldPlayer extends Player {
  Completer<void>? stopping, disposing;
  var stopEntered = Completer<void>();
  final disposeEntered = Completer<void>();
  int stops = 0, disposes = 0;
  bool failDispose = false;
  @override
  Future<void> stop() async {
    stops++;
    if (!stopEntered.isCompleted) stopEntered.complete();
    await stopping?.future;
    await super.stop();
  }

  @override
  Future<void> dispose() async {
    disposes++;
    if (!disposeEntered.isCompleted) disposeEntered.complete();
    await disposing?.future;
    await super.dispose();
    if (failDispose) throw StateError('private dispose');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final sync in [true, false]) {
    test(
      'installed immediate once/reentrant ${sync ? 'sync' : 'async'} rejection',
      () async {
        var entries = 0;
        late SpeechDisposalCaller c;
        Future<void>? joined;
        final held = Completer<void>();
        c = SpeechDisposalCaller.operation(() {
          entries++;
          joined = c.dispose();
          if (sync) throw StateError('private');
          return held.future;
        });
        final done = c.dispose();
        expect(entries, 1);
        expect(identical(done, joined), isTrue);
        expect(identical(done, c.dispose()), isTrue);
        var settled = false;
        done.then((_) => settled = true);
        await Future<void>.value();
        if (!sync) {
          expect(settled, isFalse);
          held.completeError(StateError('private'));
        }
        await done;
        expect(entries, 1);
        expect(identical(done, c.dispose()), isTrue);
      },
    );
  }
  for (final fail in ['none', 'stop', 'dispose', 'delete']) {
    test('actual owner held stop/release/dispose completion $fail', () async {
      final client = Client(), clips = HeldClips(), player = HeldPlayer();
      final owner = SpeechService(
        client: client,
        storage: clips,
        playback: player,
      );
      await owner.playBytes([1]);
      final stops = player.stops;
      player.stopEntered = Completer<void>();
      player.stopping = Completer<void>();
      player.disposing = Completer<void>();
      clips.deleting = Completer<void>();
      player.failStop = fail == 'stop';
      player.failDispose = fail == 'dispose';
      clips.failDelete = fail == 'delete';
      final c = SpeechDisposalCaller(owner: owner);
      final done = c.dispose();
      expect(
        client.closes,
        1,
        reason: 'terminal invalidation happens during invocation',
      );
      expect(identical(done, c.dispose()), isTrue);
      var settled = false;
      done.then((_) => settled = true);
      await player.stopEntered.future;
      await Future<void>.value();
      expect(settled, isFalse);
      expect(player.stops, stops + 1);
      expect(player.disposes, 0);
      expect(clips.files.keys, ['clip-0']);
      player.stopping!.complete();
      await clips.deletingEntered.future;
      expect(settled, isFalse);
      expect(player.events.hasListener, isFalse);
      expect(player.disposes, 0);
      clips.deleting!.complete();
      await player.disposeEntered.future;
      expect(settled, isFalse);
      expect(clips.deletes, 1);
      expect(player.disposes, 1);
      player.disposing!.complete();
      await done;
      expect(player.disposed, isTrue);
      expect(clips.files.isEmpty, fail != 'delete');
      if (fail == 'delete') expect(owner.cleanupProblem, isNotNull);
      await expectLater(owner.playBytes([2]), throwsStateError);
      expect(player.played, ['clip-0']);
      expect(clips.sequence, 1);
      expect(identical(done, c.dispose()), isTrue);
      expect(client.closes, 1);
    });
  }
  for (final stage in ['resolve', 'write', 'start']) {
    test(
      'actual old $stage terminal completion preserves owner semantics',
      () async {
        final clips = Clips(), player = Player(), client = Client();
        final held = Completer<void>();
        if (stage == 'resolve') clips.resolving = held;
        if (stage == 'write') clips.writing = held;
        if (stage == 'start') player.starting = held;
        final owner = SpeechService(
          client: client,
          storage: clips,
          playback: player,
        );
        final old = owner.playBytes([1]);
        await switch (stage) {
          'resolve' => clips.resolveEntered.future,
          'write' => clips.writeEntered.future,
          _ => player.entered.future,
        };
        final c = SpeechDisposalCaller(owner: owner);
        var settled = false;
        final done = c.dispose()..then((_) => settled = true);
        await Future<void>.value();
        await Future<void>.value();
        if (stage == 'start') expect(settled, isFalse);
        expect(client.closes, 1);
        held.complete();
        await Future.wait([old, done]);
        expect(clips.files, isEmpty);
        expect(player.active, isNull);
        expect(player.disposed, isTrue);
        if (stage != 'start') expect(player.played, isEmpty);
        await expectLater(owner.playBytes([2]), throwsStateError);
        expect(clips.sequence, 1);
      },
    );
  }
  test(
    'actual main retained owner immediate same teardown order source only',
    () {
      final s = File('lib/main.dart').readAsStringSync();
      expect(s, contains('SpeechDisposalCaller(owner: _speech)'));
      expect(
        s,
        contains(
          'unawaited(_disposeKeyCapture());\n    unawaited(_speechDisposal.dispose());\n    super.dispose();',
        ),
      );
      expect(s, isNot(contains('_speech.dispose();')));
      expect(s, contains('unawaited(_speechMute.mute());'));
    },
  );
}
