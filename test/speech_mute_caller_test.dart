import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/speech.dart';
import 'package:local_bluey/services/speech_mute_caller.dart';

import 'speech_disposal_caller_test.dart' show HeldClips, HeldPlayer;
import 'speech_playback_test.dart' show Clips, Player;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('immediate entry pending before notification reentrant join and each broadcast', () async {
    final held = Completer<void>();
    var stops = 0, broadcasts = 0, notifications = 0;
    late SpeechMuteCaller c;
    c = SpeechMuteCaller.operations(() {
      stops++;
      return held.future;
    }, () => broadcasts++);
    Future<void>? joined;
    c.addListener(() {
      notifications++;
      if (c.loading && joined == null) joined = c.mute();
    });
    final done = c.mute();
    expect(stops, 1);
    expect(broadcasts, 2);
    expect(identical(done, joined), isTrue);
    expect(identical(done, c.mute()), isTrue);
    expect(broadcasts, 3);
    var settled = false;
    done.then((_) => settled = true);
    await Future<void>.value();
    expect(settled, isFalse);
    held.completeError(StateError('private'));
    await done;
    expect(c.failed, isTrue);
    expect(c.loading, isFalse);
    expect(notifications, 2);
    c.dispose();
  });
  test('sync throw safely failed explicit retry only', () async {
    var stops = 0, broadcasts = 0;
    final c = SpeechMuteCaller.operations(() {
      stops++;
      if (stops == 1) throw StateError('private');
      return Future.value();
    }, () => broadcasts++);
    await c.mute();
    expect(c.failed, isTrue);
    expect(stops, 1);
    await c.mute();
    expect(c.visible, isFalse);
    expect(stops, 2);
    expect(broadcasts, 2);
    c.dispose();
  });
  for (final fail in [false, true]) {
    test(
      'actual owner stop/release held joined completion error$fail',
      () async {
        final clips = HeldClips(), player = HeldPlayer();
        final owner = SpeechService(storage: clips, playback: player);
        await owner.playBytes([1]);
        final stops = player.stops;
        player.stopEntered = Completer<void>();
        player.stopping = Completer<void>();
        clips.deleting = Completer<void>();
        player.failStop = fail;
        var broadcasts = 0;
        final c = SpeechMuteCaller(owner: owner, broadcast: () => broadcasts++);
        final done = c.mute();
        expect(broadcasts, 1);
        expect(identical(done, c.mute()), isTrue);
        expect(broadcasts, 2);
        var settled = false;
        done.then((_) => settled = true);
        await player.stopEntered.future;
        expect(settled, isFalse);
        expect(player.stops, stops + 1);
        player.stopping!.complete();
        await clips.deletingEntered.future;
        expect(settled, isFalse);
        expect(player.events.hasListener, isFalse);
        clips.deleting!.complete();
        await done;
        expect(c.failed, fail);
        expect(clips.files, isEmpty);
        expect(player.played, ['clip-0']);
        player.failStop = false;
        player.stopping = null;
        clips.deleting = null;
        if (fail) {
          await c.mute();
          expect(c.visible, isFalse);
          expect(broadcasts, 3);
        }
        c.dispose();
        await owner.dispose();
      },
    );
  }
  test('best-effort delete failure does not become erasure proof', () async {
    final clips = Clips(), player = Player();
    final owner = SpeechService(storage: clips, playback: player);
    await owner.playBytes([1]);
    clips.failDelete = true;
    final c = SpeechMuteCaller(owner: owner, broadcast: () {});
    await c.mute();
    expect(c.visible, isFalse);
    expect(clips.files, isNotEmpty);
    expect(owner.cleanupProblem, isNotNull);
    c.dispose();
    await owner.dispose();
  });
  for (final entered in [false, true]) {
    test(
      'disposed caller fences ${entered ? 'entered completion' : 'new entry'}',
      () async {
        final held = Completer<void>();
        var stops = 0, broadcasts = 0, notifications = 0;
        final c = SpeechMuteCaller.operations(() {
          stops++;
          return held.future;
        }, () => broadcasts++);
        c.addListener(() => notifications++);
        Future<void>? done;
        if (entered) done = c.mute();
        c.dispose();
        await c.mute();
        expect(stops, entered ? 1 : 0);
        expect(broadcasts, entered ? 1 : 0);
        if (entered) {
          held.completeError(StateError('private'));
          await done;
        }
        expect(notifications, entered ? 1 : 0);
      },
    );
  }
  test(
    'reentrant disposal notification safe actual completion remains pending',
    () async {
      final held = Completer<void>();
      final c = SpeechMuteCaller.operations(() => held.future, () {});
      c.addListener(c.dispose);
      final done = c.mute();
      var settled = false;
      done.then((_) => settled = true);
      await Future<void>.value();
      expect(settled, isFalse);
      held.complete();
      await done;
      c.dispose();
    },
  );
  for (final stage in ['resolve', 'write', 'start']) {
    test(
      'actual old $stage stop then terminal dispose no fresh playback',
      () async {
        final clips = Clips(), player = Player();
        final held = Completer<void>();
        if (stage == 'resolve') clips.resolving = held;
        if (stage == 'write') clips.writing = held;
        if (stage == 'start') player.starting = held;
        final owner = SpeechService(storage: clips, playback: player);
        final old = owner.playBytes([1]);
        await switch (stage) {
          'resolve' => clips.resolveEntered.future,
          'write' => clips.writeEntered.future,
          _ => player.entered.future,
        };
        var broadcasts = 0;
        final c = SpeechMuteCaller(owner: owner, broadcast: () => broadcasts++);
        final done = c.mute();
        var settled = false;
        done.then((_) => settled = true);
        await Future<void>.value();
        await Future<void>.value();
        if (stage == 'start') expect(settled, isFalse);
        c.dispose();
        final closing = owner.dispose();
        held.complete();
        await Future.wait([old, done, closing]);
        expect(clips.files, isEmpty);
        expect(player.active, isNull);
        expect(broadcasts, 1);
        if (stage != 'start') expect(player.played, isEmpty);
      },
    );
  }
  test(
    'main both notices actual retained owner same terminal order source-only',
    () {
      final s = File('lib/main.dart').readAsStringSync();
      expect(
        s,
        contains(
          "owner: _speech,\n    broadcast: () => _server.broadcast(Packet(command: 'stopSpeech'))",
        ),
      );
      expect(s, contains('unawaited(_speechMute.mute());'));
      expect('SpeechMuteNotice('.allMatches(s).length, 2);
      expect(
        s.indexOf('_speechMute.dispose();'),
        lessThan(s.indexOf('unawaited(_speechDisposal.dispose());')),
      );
    },
  );
}
