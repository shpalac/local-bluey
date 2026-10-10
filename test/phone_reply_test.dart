import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/services/phone_reply.dart';

class _Player implements ReplyPlayer {
  final controller = StreamController<void>.broadcast();
  final events = <String>[];
  final played = <String>[];
  Completer<void>? holdPlay;
  Object? playError;
  bool completeInsidePlay = false;
  int listenersAtPlay = -1;
  bool disposed = false;

  @override
  Stream<void> get completions => controller.stream;

  @override
  Future<void> play(String path) async {
    listenersAtPlay = controller.hasListener ? 1 : 0;
    events.add('play');
    played.add(path);
    if (completeInsidePlay) controller.add(null);
    await holdPlay?.future;
    if (playError != null) throw playError!;
  }

  @override
  Future<void> stop() async => events.add('stop');

  @override
  Future<void> dispose() async => disposed = true;
}

String _audio([int n = 32]) => base64Encode(List.filled(n, 5));

void main() {
  late Directory dir;
  late _Player player;
  late List<Packet> sent;
  late List<String> shown;
  late bool active;
  late PhoneReplyReceiver receiver;
  final ids = <String, int>{};

  PhoneReplyReceiver build({
    Future<void> Function(File, List<int>)? write,
    Future<void> Function(File)? delete,
    Future<Directory> Function()? tempDir,
  }) => PhoneReplyReceiver(
    player: player,
    send: sent.add,
    showText: shown.add,
    isActive: () => active,
    tempDir: tempDir ?? () async => dir,
    write: write,
    delete: delete,
  );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));
  List<String> receipts() => sent
      .map(
        (p) =>
            '${p.command}:${ids.entries.firstWhere((e) => e.value == p.speech).key}',
      )
      .toList();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('phone_reply_');
    player = _Player();
    sent = [];
    shown = [];
    active = true;
    receiver = build();
  });
  tearDown(() => dir.delete(recursive: true));

  Packet say(String speech, {String? audio, String text = 'hello'}) => Packet(
    command: 'say',
    text: text,
    audio: audio,
    speech: ids.putIfAbsent(speech, () => ids.length + 1),
  );

  test(
    'success: playing after start, done on completion, clip removed',
    () async {
      receiver.handle(say('s1', audio: _audio()));
      await settle();
      expect(player.listenersAtPlay, 1, reason: 'subscribed before play');
      expect(receipts(), ['playing:s1']);
      expect(dir.listSync(), hasLength(1));
      player.controller.add(null);
      await settle();
      expect(receipts(), ['playing:s1', 'done:s1']);
      expect(shown, ['hello']);
      expect(dir.listSync(), isEmpty);
    },
  );

  test('an immediate completion inside play is not lost', () async {
    player.completeInsidePlay = true;
    receiver.handle(say('s1', audio: _audio()));
    await settle();
    expect(receipts(), ['playing:s1', 'done:s1']);
    expect(dir.listSync(), isEmpty);
  });

  test(
    'text-only replies are acknowledged by display, no player use',
    () async {
      receiver.handle(say('t1'));
      await settle();
      expect(shown, ['hello']);
      expect(receipts(), ['done:t1']);
      expect(player.events, isEmpty);
    },
  );

  test(
    'malformed, empty and oversize audio: safe note, no false receipts',
    () async {
      for (final bad in [
        '%%% nope %%%',
        '',
        'A' * (PhoneReplyReceiver.maxBytes * 2),
      ]) {
        shown.clear();
        receiver.handle(say('x', audio: bad));
        await settle();
        expect(shown, hasLength(2));
        expect(shown.first, 'hello');
        expect(shown.last, contains('not valid'));
        expect(shown.last, isNot(contains('Exception')));
      }
      expect(sent, isEmpty);
      expect(player.played, isEmpty);
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'create failure, entered partial write: safe note, no leftover',
    () async {
      receiver = build(tempDir: () async => throw StateError('/private/dir'));
      receiver.handle(say('a', audio: _audio()));
      await settle();
      expect(shown.last, isNot(contains('private')));
      expect(sent, isEmpty);

      shown.clear();
      File? partial;
      receiver = build(
        write: (file, bytes) async {
          partial = file;
          await file.writeAsBytes(bytes.sublist(0, 3));
          expect(file.existsSync(), isTrue);
          throw const FileSystemException('disk full', '/private/secret');
        },
      );
      receiver.handle(say('b', audio: _audio()));
      await settle();
      expect(shown.last, contains('Could not save'));
      expect(shown.last, isNot(contains('secret')));
      expect(partial!.existsSync(), isFalse);
      expect(sent, isEmpty);
      expect(player.played, isEmpty);
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'a player start error is one safe note, no playing, clip removed',
    () async {
      player.playError = StateError('/private/engine');
      receiver.handle(say('p', audio: _audio()));
      await settle();
      expect(shown.last, contains('Could not play'));
      expect(shown.last, isNot(contains('private')));
      expect(sent, isEmpty);
      expect(dir.listSync(), isEmpty);
    },
  );

  test('a newer say replaces a held one: no old receipts or leaks', () async {
    player.holdPlay = Completer<void>();
    receiver.handle(say('old', audio: _audio()));
    await settle();
    expect(player.played, hasLength(1));
    receiver.handle(say('new', audio: _audio(48)));
    player.holdPlay!.complete();
    player.holdPlay = null;
    await settle();
    expect(player.played, hasLength(2));
    expect(player.played[0], isNot(player.played[1]), reason: 'unique clips');
    expect(receipts(), ['playing:new'], reason: 'old never signals');
    expect(dir.listSync(), hasLength(1));
    player.controller.add(null);
    await settle();
    expect(receipts(), ['playing:new', 'done:new']);
    expect(dir.listSync(), isEmpty);
  });

  test(
    'a late completion of the replaced reply cannot finish the new one',
    () async {
      receiver.handle(say('old', audio: _audio()));
      await settle();
      receiver.handle(say('new', audio: _audio()));
      await settle();
      expect(receipts(), ['playing:old', 'playing:new']);
      player.controller.add(null);
      await settle();
      expect(receipts(), ['playing:old', 'playing:new', 'done:new']);
    },
  );

  test('stopSpeech stops playback, removes the clip, no later done', () async {
    receiver.handle(say('s', audio: _audio()));
    await settle();
    receiver.handle(Packet(command: 'stopSpeech'));
    await settle();
    expect(player.events, contains('stop'));
    expect(dir.listSync(), isEmpty);
    player.controller.add(null);
    await settle();
    expect(receipts(), ['playing:s']);
  });

  test('stopSpeech during a held write: nothing starts', () async {
    final hold = Completer<void>();
    receiver = build(
      write: (f, b) async {
        await hold.future;
        await f.writeAsBytes(b);
      },
    );
    receiver.handle(say('s', audio: _audio()));
    await settle();
    receiver.handle(Packet(command: 'stopSpeech'));
    hold.complete();
    await settle();
    expect(player.played, isEmpty);
    expect(sent, isEmpty);
    expect(dir.listSync(), isEmpty);
  });

  test('dispose during staging: no play, no UI, no leaked clip', () async {
    final hold = Completer<void>();
    receiver = build(
      write: (f, b) async {
        await hold.future;
        await f.writeAsBytes(b);
      },
    );
    receiver.handle(say('s', audio: _audio()));
    await settle();
    final shownBefore = shown.length;
    active = false;
    final disposing = receiver.dispose();
    hold.complete();
    await disposing;
    expect(player.played, isEmpty);
    expect(shown.length, shownBefore);
    expect(sent, isEmpty);
    expect(dir.listSync(), isEmpty);
    expect(player.disposed, isTrue);
    receiver.handle(say('late', audio: _audio()));
    await settle();
    expect(player.played, isEmpty);
  });

  test('dispose while playing: late completion sends nothing', () async {
    receiver.handle(say('s', audio: _audio()));
    await settle();
    active = false;
    await receiver.dispose();
    player.controller.add(null);
    await settle();
    expect(receipts(), ['playing:s']);
    expect(dir.listSync(), isEmpty);
  });

  test('a failed delete is reported safely and retried', () async {
    var fail = true;
    receiver = build(
      delete: (f) async {
        if (fail) throw FileSystemException('busy', f.path);
        await f.delete();
      },
    );
    receiver.handle(say('s', audio: _audio()));
    await settle();
    player.controller.add(null);
    await settle();
    expect(receiver.undeletedCount, 1);
    expect(dir.listSync(), hasLength(1));
    fail = false;
    receiver.handle(Packet(command: 'stopSpeech'));
    await settle();
    expect(receiver.undeletedCount, 0);
    expect(dir.listSync(), isEmpty);
  });

  test('listener path: errors from callbacks never escape', () async {
    final uncaught = <Object>[];
    receiver = PhoneReplyReceiver(
      player: player,
      send: (_) => throw StateError('link down'),
      showText: shown.add,
      tempDir: () async => dir,
    );
    await runZonedGuarded(() async {
      final stream = StreamController<Packet>();
      stream.stream.listen(receiver.handle);
      stream.add(say('s', audio: _audio()));
      stream.add(say('t'));
      stream.add(Packet(command: 'stopSpeech'));
      await settle();
      await stream.close();
    }, (e, _) => uncaught.add(e));
    expect(uncaught, isEmpty);
    expect(dir.listSync(), isEmpty);
  });
}
