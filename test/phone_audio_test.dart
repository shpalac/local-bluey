import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/phone_audio.dart';

List<int> _m4a(int length) => [
  0,
  0,
  0,
  0x18,
  ...'ftypM4A '.codeUnits,
  ...List.filled(length - 12, 7),
];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('phone_audio_'));
  tearDown(() => dir.delete(recursive: true));

  Future<PhoneAudioException> refused(String encoded) async {
    try {
      await PhoneAudioIntake.stage(encoded, tempDir: () async => dir);
    } on PhoneAudioException catch (e) {
      return e;
    }
    fail('expected a refusal');
  }

  test('a valid m4a payload is staged byte for byte', () async {
    final bytes = _m4a(64);
    final file = await PhoneAudioIntake.stage(
      base64Encode(bytes),
      tempDir: () async => dir,
    );
    expect(await file.readAsBytes(), bytes);
    expect(file.path, endsWith('.m4a'));
  });

  test(
    'malformed base64 is refused without a file or raw error text',
    () async {
      final e = await refused('%%% not base64 %%%');
      expect(e.problem, PhoneAudioProblem.malformed);
      expect(e.message, isNot(contains('FormatException')));
      expect(dir.listSync(), isEmpty);
    },
  );

  test('oversized payloads are refused before and after decoding', () async {
    final huge = 'A' * (PhoneAudioIntake.maxBytes * 2);
    expect((await refused(huge)).problem, PhoneAudioProblem.tooLarge);
    final justOver = base64Encode(_m4a(PhoneAudioIntake.maxBytes + 1));
    expect((await refused(justOver)).problem, PhoneAudioProblem.tooLarge);
    expect(dir.listSync(), isEmpty);
  });

  test('bytes that are not an MP4 container are refused', () async {
    expect(
      (await refused(base64Encode(List.filled(64, 1)))).problem,
      PhoneAudioProblem.notAudio,
    );
    expect(
      (await refused(base64Encode([1, 2, 3]))).problem,
      PhoneAudioProblem.notAudio,
    );
    expect(dir.listSync(), isEmpty);
  });

  test('a write failure is reported once and leaves no file', () async {
    // A regular file where the directory should be makes create/write fail.
    final blocker = File('${dir.path}/blocked')..writeAsStringSync('x');
    PhoneAudioException? error;
    try {
      await PhoneAudioIntake.stage(
        base64Encode(_m4a(64)),
        tempDir: () async => Directory(blocker.path),
      );
    } on PhoneAudioException catch (e) {
      error = e;
    }
    expect(error?.problem, PhoneAudioProblem.storage);
    expect(error?.message, isNot(contains(dir.path)));
    expect(dir.listSync().map((e) => e.path), [blocker.path]);
  });

  test('an entered partial write is removed and reported once', () async {
    File? partial;
    PhoneAudioException? error;
    try {
      await PhoneAudioIntake.stage(
        base64Encode(_m4a(64)),
        tempDir: () async => dir,
        write: (file, bytes) async {
          partial = file;
          await file.writeAsBytes(bytes.sublist(0, 10), flush: true);
          expect(file.existsSync(), isTrue, reason: 'partial bytes entered');
          throw const FileSystemException('disk full', '/private/secret');
        },
      );
    } on PhoneAudioException catch (e) {
      error = e;
    }
    expect(error?.problem, PhoneAudioProblem.storage);
    expect(error?.message, isNot(contains('secret')));
    expect(partial!.existsSync(), isFalse);
    expect(dir.listSync(), isEmpty);
  });

  test('concurrent stages own independent files under equal clocks', () async {
    final at = DateTime.utc(2026, 10, 10);
    final a = _m4a(40);
    final b = _m4a(48);
    final files = await Future.wait([
      PhoneAudioIntake.stage(
        base64Encode(a),
        tempDir: () async => dir,
        now: () => at,
      ),
      PhoneAudioIntake.stage(
        base64Encode(b),
        tempDir: () async => dir,
        now: () => at,
      ),
    ]);
    expect(files[0].path, isNot(files[1].path));
    expect(await files[0].readAsBytes(), a);
    expect(await files[1].readAsBytes(), b);
  });

  group('PhoneAudioReceiver listener path', () {
    late List<String> bubbles;
    late List<Object> uncaught;
    late List<File> processed;

    PhoneAudioReceiver receiver({
      bool Function()? isActive,
      Future<File> Function(String)? stage,
      Future<void> Function(File)? process,
    }) => PhoneAudioReceiver(
      stage:
          stage ?? (e) => PhoneAudioIntake.stage(e, tempDir: () async => dir),
      process:
          process ??
          (f) async {
            processed.add(f);
            await f.delete(); // the runner deletes its recording
          },
      onRejected: bubbles.add,
      isActive: isActive ?? () => true,
    );

    setUp(() {
      bubbles = [];
      uncaught = [];
      processed = [];
    });

    Future<void> feed(PhoneAudioReceiver r, String payload) async {
      await runZonedGuarded(() async {
        final stream = StreamController<String>();
        stream.stream.listen(r.handle);
        stream.add(payload);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await stream.close();
      }, (e, _) => uncaught.add(e));
    }

    test(
      'malformed, oversize and non-audio give one safe bubble each',
      () async {
        for (final payload in [
          '%%% not base64 %%%',
          'A' * (PhoneAudioIntake.maxBytes * 2),
          base64Encode(List.filled(64, 1)),
        ]) {
          bubbles.clear();
          await feed(receiver(), payload);
          expect(bubbles, hasLength(1), reason: payload.substring(0, 8));
          expect(bubbles.single, isNot(contains('Exception')));
          expect(uncaught, isEmpty);
          expect(processed, isEmpty);
          expect(dir.listSync(), isEmpty);
        }
      },
    );

    test('a storage failure is one safe bubble and no leftover', () async {
      final r = receiver(
        stage: (e) => PhoneAudioIntake.stage(
          e,
          tempDir: () async => dir,
          write: (f, b) async {
            await f.writeAsBytes(b.sublist(0, 4));
            throw StateError('/private/path');
          },
        ),
      );
      await feed(r, base64Encode(_m4a(64)));
      expect(bubbles, [
        const PhoneAudioException(PhoneAudioProblem.storage).message,
      ]);
      expect(uncaught, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('a valid payload reaches the runner and is cleaned up', () async {
      await feed(receiver(), base64Encode(_m4a(64)));
      expect(processed, hasLength(1));
      expect(bubbles, isEmpty);
      expect(uncaught, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('a runner failure is contained and the file removed', () async {
      await feed(
        receiver(process: (f) async => throw StateError('boom')),
        base64Encode(_m4a(64)),
      );
      expect(uncaught, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('a receiver disposed during staging neither runs nor leaks', () async {
      var active = true;
      final release = Completer<void>();
      final r = receiver(
        isActive: () => active,
        stage: (e) async {
          final file = await PhoneAudioIntake.stage(
            e,
            tempDir: () async => dir,
          );
          await release.future;
          return file;
        },
      );
      await feed(r, base64Encode(_m4a(64)));
      expect(dir.listSync(), hasLength(1), reason: 'staged and held');
      active = false;
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(processed, isEmpty);
      expect(bubbles, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('a disposed receiver shows no bubble for a refusal', () async {
      await feed(receiver(isActive: () => false), '%%%');
      expect(bubbles, isEmpty);
      expect(uncaught, isEmpty);
    });
  });
}
