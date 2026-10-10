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
}
