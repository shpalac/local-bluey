import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/services/phone_reply.dart';

class _Session implements ReplySession {
  final controller = StreamController<void>.broadcast();
  final events = <String>[];
  String? path;
  Completer<void>? holdPlay;
  Object? playError;
  Object? stopError;
  Object? disposeError;
  bool completeInsidePlay = false;
  bool listenedAtPlay = false;
  bool disposed = false;

  @override
  Stream<void> get completions => controller.stream;

  @override
  Future<void> play(String p) async {
    path = p;
    listenedAtPlay = controller.hasListener;
    events.add('play');
    if (completeInsidePlay) controller.add(null);
    await holdPlay?.future;
    if (playError != null) throw playError!;
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
    if (disposeError != null) throw disposeError!;
    disposed = true;
  }
}

class _World {
  final sessions = <_Session>[];
  void Function(_Session session, int index)? configure;
  ReplySession create() {
    final session = _Session();
    configure?.call(session, sessions.length);
    sessions.add(session);
    return session;
  }

  List<String> get played =>
      sessions.where((s) => s.path != null).map((s) => s.path!).toList();
}

String _audio([int n = 32]) => base64Encode(List.filled(n, 5));

void main() {
  late Directory dir;
  late _World world;
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
    createSession: world.create,
    send: sent.add,
    showText: shown.add,
    isActive: () => active,
    tempDir: tempDir ?? () async => dir,
    write: write,
    delete: delete,
  );

  // Waits for the receiver to go idle; a deliberately held operation never
  // does, so the wait is bounded and the held state is what gets asserted.
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await receiver.idle.timeout(
      const Duration(milliseconds: 400),
      onTimeout: () {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  List<String> receipts() => sent
      .map(
        (p) =>
            '${p.command}:${ids.entries.firstWhere((e) => e.value == p.speech).key}',
      )
      .toList();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('phone_reply_');
    world = _World();
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

  _Session sess(int i) => world.sessions[i];

  test(
    'success: playing after start, done on completion, clip removed',
    () async {
      receiver.handle(say('s1', audio: _audio()));
      await settle();
      expect(sess(0).listenedAtPlay, isTrue, reason: 'subscribed before play');
      expect(receipts(), ['playing:s1']);
      expect(dir.listSync(), hasLength(1));
      sess(0).controller.add(null);
      await settle();
      expect(receipts(), ['playing:s1', 'done:s1']);
      expect(shown, ['hello']);
      expect(dir.listSync(), isEmpty);
      expect(sess(0).disposed, isTrue);
    },
  );

  test('an immediate completion inside play is not lost', () async {
    world.configure = (s, i) => s.completeInsidePlay = true;
    receiver.handle(say('s1', audio: _audio()));
    await settle();
    expect(receipts(), ['playing:s1', 'done:s1']);
    expect(dir.listSync(), isEmpty);
  });

  test('text-only replies are acknowledged by display, no session', () async {
    receiver.handle(say('t1'));
    await settle();
    expect(shown, ['hello']);
    expect(receipts(), ['done:t1']);
    expect(world.sessions, isEmpty);
  });

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
      expect(world.played, isEmpty);
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
      expect(world.played, isEmpty);
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'a player start error is one safe note, no playing, clip removed',
    () async {
      world.configure = (s, i) => s.playError = StateError('/private/engine');
      receiver.handle(say('p', audio: _audio()));
      await settle();
      expect(shown.last, contains('Could not play'));
      expect(shown.last, isNot(contains('private')));
      expect(sent, isEmpty);
      expect(dir.listSync(), isEmpty);
    },
  );

  test('a newer say replaces a held one: no old receipts or leaks', () async {
    final hold = Completer<void>();
    world.configure = (s, i) {
      if (i == 0) s.holdPlay = hold;
    };
    receiver.handle(say('old', audio: _audio()));
    await settle();
    expect(world.played, hasLength(1));
    receiver.handle(say('new', audio: _audio(48)));
    hold.complete();
    await settle();
    expect(world.played, hasLength(2));
    expect(world.played[0], isNot(world.played[1]), reason: 'unique clips');
    expect(receipts(), ['playing:new'], reason: 'old never signals');
    expect(dir.listSync(), hasLength(1));
    sess(1).controller.add(null);
    await settle();
    expect(receipts(), ['playing:new', 'done:new']);
    expect(dir.listSync(), isEmpty);
  });

  test(
    'a late event from the replaced clip cannot finish or delete the new one',
    () async {
      receiver.handle(say('old', audio: _audio()));
      await settle();
      receiver.handle(say('new', audio: _audio()));
      await settle();
      expect(receipts(), ['playing:old', 'playing:new']);
      sess(0).controller.add(null); // late event on the old session
      await settle();
      expect(receipts(), ['playing:old', 'playing:new']);
      expect(dir.listSync(), hasLength(1), reason: 'live clip kept');
      sess(1).controller.add(null);
      await settle();
      expect(receipts(), ['playing:old', 'playing:new', 'done:new']);
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'a held old failure after replacement does not overwrite newer text',
    () async {
      final hold = Completer<void>();
      world.configure = (s, i) {
        if (i == 0) {
          s.holdPlay = hold;
          s.playError = StateError('late engine failure');
        }
      };
      receiver.handle(say('old', audio: _audio(), text: 'old text'));
      await settle();
      receiver.handle(say('new', audio: _audio(), text: 'new text'));
      hold.complete();
      await settle();
      expect(shown, ['old text', 'new text'], reason: 'no old error published');
      expect(receipts(), ['playing:new']);
      // Held old write failure after replacement, too.
      shown.clear();
      final wHold = Completer<void>();
      receiver = build(
        write: (f, b) async {
          await wHold.future;
          throw StateError('late write failure');
        },
      );
      receiver.handle(say('o2', audio: _audio(), text: 'old2'));
      await settle();
      receiver.handle(Packet(command: 'stopSpeech'));
      wHold.complete();
      await settle();
      expect(shown, ['old2']);
    },
  );

  test('stopSpeech stops playback, removes the clip, no later done', () async {
    receiver.handle(say('s', audio: _audio()));
    await settle();
    receiver.handle(Packet(command: 'stopSpeech'));
    await settle();
    expect(sess(0).events, contains('stop'));
    expect(dir.listSync(), isEmpty);
    sess(0).controller.add(null);
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
    expect(world.played, isEmpty);
    expect(sent, isEmpty);
    expect(dir.listSync(), isEmpty);
  });

  test(
    'stop failure: no overlapping replacement, observable, then recovers',
    () async {
      world.configure = (s, i) {
        if (i == 0) {
          s.stopError = StateError('cannot stop');
          s.disposeError = StateError('cannot dispose');
        }
      };
      receiver.handle(say('old', audio: _audio(), text: 'old'));
      await settle();
      receiver.handle(say('new', audio: _audio(), text: 'new'));
      await settle();
      expect(world.sessions, hasLength(1), reason: 'no second clip started');
      expect(shown.last, contains('could not be stopped'));
      expect(receipts(), ['playing:old']);
      expect(receiver.cleanupPending.value, 1);
      expect(dir.listSync(), hasLength(1), reason: 'file kept while uncertain');
      // Natural completion of the stuck clip is evidence it ended: no done
      // for the replaced reply, and its file is removed.
      sess(0).controller.add(null);
      await settle();
      expect(receipts(), ['playing:old']);
      expect(dir.listSync(), isEmpty);
      expect(receiver.cleanupPending.value, 0);
      receiver.handle(say('again', audio: _audio(), text: 'again'));
      await settle();
      expect(world.sessions, hasLength(2));
      expect(receipts(), ['playing:old', 'playing:again']);
    },
  );

  test('a stuck stop that recovers is retried on the next release', () async {
    world.configure = (s, i) {
      if (i == 0) {
        s.stopError = StateError('cannot stop');
        s.disposeError = StateError('cannot dispose');
      }
    };
    receiver.handle(say('old', audio: _audio()));
    await settle();
    receiver.handle(Packet(command: 'stopSpeech'));
    await settle();
    expect(receiver.cleanupPending.value, 1);
    expect(dir.listSync(), hasLength(1));
    sess(0).stopError = null;
    sess(0).disposeError = null;
    receiver.handle(say('again', audio: _audio()));
    await settle();
    expect(receiver.cleanupPending.value, 0);
    expect(world.sessions, hasLength(2));
    expect(receipts(), ['playing:old', 'playing:again']);
    expect(dir.listSync(), hasLength(1), reason: 'only the live clip remains');
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
    expect(world.played, isEmpty);
    expect(shown.length, shownBefore);
    expect(sent, isEmpty);
    expect(dir.listSync(), isEmpty);
    receiver.handle(say('late', audio: _audio()));
    await settle();
    expect(world.played, isEmpty);
  });

  test('dispose while playing: late completion sends nothing', () async {
    receiver.handle(say('s', audio: _audio()));
    await settle();
    active = false;
    await receiver.dispose();
    sess(0).controller.add(null);
    await settle();
    expect(receipts(), ['playing:s']);
    expect(dir.listSync(), isEmpty);
    expect(sess(0).disposed, isTrue);
  });

  test('a failed delete is observable and retried', () async {
    var fail = true;
    receiver = build(
      delete: (f) async {
        if (fail) throw FileSystemException('busy', f.path);
        await f.delete();
      },
    );
    receiver.handle(say('s', audio: _audio()));
    await settle();
    sess(0).controller.add(null);
    await settle();
    expect(receiver.cleanupPending.value, 1);
    expect(dir.listSync(), hasLength(1));
    fail = false;
    receiver.handle(Packet(command: 'stopSpeech'));
    await settle();
    expect(receiver.cleanupPending.value, 0);
    expect(dir.listSync(), isEmpty);
  });

  test('a throwing done send still cleans up and never escapes', () async {
    final uncaught = <Object>[];
    receiver = PhoneReplyReceiver(
      createSession: world.create,
      send: (p) {
        if (p.command == 'done') throw StateError('link down');
        sent.add(p);
      },
      showText: shown.add,
      tempDir: () async => dir,
    );
    await runZonedGuarded(() async {
      receiver.handle(say('s', audio: _audio()));
      await settle();
      expect(receipts(), ['playing:s']);
      sess(0).controller.add(null);
      await settle();
    }, (e, _) => uncaught.add(e));
    expect(uncaught, isEmpty);
    expect(dir.listSync(), isEmpty);
    expect(sess(0).controller.hasListener, isFalse);
    expect(sess(0).disposed, isTrue);
  });

  test('listener path: errors from callbacks never escape', () async {
    final uncaught = <Object>[];
    receiver = PhoneReplyReceiver(
      createSession: world.create,
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
