import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:local_bluey/services/speech.dart';

class Clips implements SpeechClipStorage {
  int sequence = 0;
  final files = <String, List<int>>{};
  Completer<void>? resolving, writing;
  final resolveEntered = Completer<void>(), writeEntered = Completer<void>();
  bool failWrite = false, failDelete = false;
  @override
  Future<String> resolve() async {
    final path = 'clip-${sequence++}';
    if (!resolveEntered.isCompleted) resolveEntered.complete();
    await resolving?.future;
    return path;
  }

  @override
  Future<void> write(String path, List<int> bytes) async {
    if (!writeEntered.isCompleted) writeEntered.complete();
    await writing?.future;
    files[path] = bytes;
    if (failWrite) throw StateError('write');
  }

  @override
  Future<void> delete(String path) async {
    if (failDelete) throw StateError('delete');
    files.remove(path);
  }
}

class Player implements SpeechPlayback {
  final sessions = <String, StreamController<void>>{};
  final idleEvents = StreamController<void>.broadcast(sync: true);
  StreamController<void> get events =>
      sessions.isEmpty ? idleEvents : sessions.values.last;
  final entered = Completer<void>();
  Completer<void>? starting;
  final played = <String>[];
  String? active;
  bool disposed = false, immediate = false, fail = false, failStop = false;
  @override
  Stream<void> completed(String path) =>
      (sessions[path] ??= StreamController<void>.broadcast(sync: true)).stream;
  @override
  Future<void> play(String path) async {
    played.add(path);
    if (!entered.isCompleted) entered.complete();
    await starting?.future;
    active = path;
    if (immediate) events.add(null);
    if (fail) throw StateError('play');
  }

  @override
  Future<void> stop() async {
    active = null;
    if (failStop) throw StateError('stop');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await idleEvents.close();
    for (final events in sessions.values) {
      await events.close();
    }
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });
  for (final dispose in [false, true]) {
    for (final stage in ['resolve', 'write', 'start']) {
      test(
        'entered $stage invalidated by ${dispose ? 'dispose' : 'stop'} never resurrects',
        () async {
          final clips = Clips(), player = Player();
          final service = SpeechService(storage: clips, playback: player);
          final delay = Completer<void>();
          if (stage == 'resolve') clips.resolving = delay;
          if (stage == 'write') clips.writing = delay;
          if (stage == 'start') player.starting = delay;
          final playing = service.playBytes([1]);
          await switch (stage) {
            'resolve' => clips.resolveEntered.future,
            'write' => clips.writeEntered.future,
            _ => player.entered.future,
          };
          var stopped = false;
          final stopping = (dispose ? service.dispose() : service.stop()).then((
            _,
          ) {
            stopped = true;
          });
          await tick();
          if (stage == 'start') {
            expect(stopped, isFalse);
          } else {
            expect(stopped, isTrue);
          }
          delay.complete();
          await Future.wait([playing, stopping]);
          expect(player.active, isNull);
          expect(clips.files, isEmpty);
          expect(player.events.hasListener, isFalse);
          if (stage != 'start') expect(player.played, isEmpty);
          if (dispose) {
            await expectLater(service.playBytes([2]), throwsStateError);
            expect(clips.sequence, 1);
            expect(player.disposed, isTrue);
          } else {
            await service.dispose();
          }
        },
      );
    }
  }
  test(
    'same-clock overlapping writes use distinct paths and latest wins',
    () async {
      final clips = Clips()..writing = Completer<void>();
      final player = Player();
      final service = SpeechService(storage: clips, playback: player);
      final old = service.playBytes([1]);
      await clips.writeEntered.future;
      final delay = clips.writing!;
      clips.writing = null;
      await service.playBytes([2]);
      expect(player.active, 'clip-1');
      delay.complete();
      await old;
      expect(player.active, 'clip-1');
      expect(clips.files.keys, ['clip-1']);
      expect(player.played, ['clip-1']);
      player.events.add(null);
      await tick();
      expect(clips.files, isEmpty);
      expect(player.events.hasListener, isFalse);
      await service.dispose();
    },
  );
  test('older entered start settles before newer clip; old completion cannot delete newer', () async {
    final clips = Clips();
    final player = Player()..starting = Completer<void>();
    final service = SpeechService(storage: clips, playback: player);
    final old = service.playBytes([1]);
    await player.entered.future;
    final next = service.playBytes([2]);
    player.events.add(null);
    player.starting!.complete();
    player.starting = null;
    await Future.wait([old, next]);
    await tick();
    expect(player.active, 'clip-1');
    expect(clips.files.keys, ['clip-1']);
    await service.stop();
    expect(clips.files, isEmpty);
    expect(player.events.hasListener, isFalse);
    await service.dispose();
  });
  test(
    'immediate completion listened before play cleans file/listener',
    () async {
      final clips = Clips();
      final player = Player()..immediate = true;
      final service = SpeechService(storage: clips, playback: player);
      await service.playBytes([1]);
      await tick();
      expect(clips.files, isEmpty);
      expect(player.events.hasListener, isFalse);
      await service.dispose();
    },
  );
  test(
    'write and play failures clean files and settle; cleanup failure reported',
    () async {
      final clips = Clips()..failWrite = true;
      final player = Player();
      final service = SpeechService(storage: clips, playback: player);
      await expectLater(service.playBytes([1]), throwsStateError);
      expect(clips.files, isEmpty);
      expect(player.played, isEmpty);
      clips.failWrite = false;
      player.fail = true;
      await expectLater(service.playBytes([2]), throwsStateError);
      expect(clips.files, isEmpty);
      expect(player.events.hasListener, isFalse);
      expect(player.active, isNull);
      player.fail = false;
      await service.playBytes([3]);
      clips.failDelete = true;
      await service.stop();
      expect(service.cleanupProblem, contains('cleanup failed'));
      clips.failDelete = false;
      await service.dispose();
    },
  );
  test(
    'completion error is consumed and releases ownership/listener',
    () async {
      final clips = Clips(), player = Player();
      final service = SpeechService(storage: clips, playback: player);
      await service.playBytes([1]);
      player.events.addError(StateError('completion'));
      await tick();
      expect(clips.files, isEmpty);
      expect(player.events.hasListener, isFalse);
      await service.dispose();
    },
  );
  test('stop/dispose errors still release listener/file; repeated dispose shares result', () async {
    final clips = Clips(), player = Player();
    final service = SpeechService(storage: clips, playback: player);
    await service.playBytes([1]);
    player.failStop = true;
    await expectLater(service.stop(), throwsStateError);
    expect(clips.files, isEmpty);
    expect(player.events.hasListener, isFalse);
    final first = service.dispose(), second = service.dispose();
    expect(identical(first, second), isTrue);
    await expectLater(first, throwsStateError);
    expect(player.disposed, isTrue);
    await expectLater(service.playBytes([2]), throwsStateError);
  });
  for (final error in [false, true]) {
    test(
      'late old completion/error after replacement does not touch newer clip $error',
      () async {
        final clips = Clips(), player = Player();
        final service = SpeechService(storage: clips, playback: player);
        await service.playBytes([1]);
        final old = player.events;
        await service.playBytes([2]);
        if (error) {
          old.addError(StateError('old completion'));
        } else {
          old.add(null);
        }
        await tick();
        expect(player.active, 'clip-1');
        expect(clips.files.keys, ['clip-1']);
        expect(player.events.hasListener, isTrue);
        await service.dispose();
      },
    );
  }
  test(
    'completion error stops active playback even if stop reports failure',
    () async {
      final clips = Clips(), player = Player();
      final service = SpeechService(storage: clips, playback: player);
      await service.playBytes([1]);
      player.failStop = true;
      player.events.addError(StateError('completion'));
      await tick();
      expect(player.active, isNull);
      expect(clips.files, isEmpty);
      expect(player.events.hasListener, isFalse);
      expect(service.cleanupProblem, isNotNull);
      player.failStop = false;
      await service.dispose();
    },
  );
  test(
    'production storage reserves unique files and cleans owned directory',
    () async {
      // Real temporary files, no AudioPlayer or native channel.
      final storage = FileSpeechClipStorage();
      final paths = await Future.wait([storage.resolve(), storage.resolve()]);
      expect(paths[0], isNot(paths[1]));
      for (final path in paths) {
        await storage.write(path, [1, 2]);
        expect(await File(path).readAsBytes(), [1, 2]);
        await storage.delete(path);
        expect(await File(path).parent.exists(), isFalse);
      }
    },
  );
}
