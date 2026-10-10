import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/pcm_decode.dart';
import 'package:local_bluey/services/stt.dart';

class Driver implements PcmDecoderDriver {
  Driver(this.run);
  final Future<PcmAudio> Function() run;
  int calls = 0;
  @override
  Future<PcmAudio> decode(String path) {
    calls++;
    return run();
  }
}

class InputFile implements File {
  InputFile({this.size = 1, this.present = true, this.fail});
  final int size;
  final bool present;
  final String? fail;
  @override
  String get path => '/private/raw-key-path';
  @override
  Future<bool> exists() async {
    if (fail == 'exists') throw FileSystemException(path);
    return present;
  }

  @override
  Future<int> length() async {
    if (fail == 'length') throw FileSystemException(path);
    return size;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PcmAudio pcm({int size = 2, int rate = 16000, int ms = 250}) => PcmAudio(
  bytes: Uint8List(size),
  sampleRate: rate,
  duration: Duration(milliseconds: ms),
);
final generic = isA<SttException>()
    .having((e) => e.kind, 'kind', SttErrorKind.decoderError)
    .having((e) => e.message, 'safe detail', 'Audio decode failed.');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pcm.boundary.fixture');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  final cases = <String, Map<String, dynamic>>{
    'empty': {'pcm': Uint8List(0), 'sampleRate': 16000, 'durationMs': 250},
    'odd': {'pcm': Uint8List(3), 'sampleRate': 16000, 'durationMs': 250},
    'wrong bytes': {
      'pcm': [1, 2],
      'sampleRate': 16000,
      'durationMs': 250,
    },
    'wrong rate type': {
      'pcm': Uint8List(2),
      'sampleRate': '16000',
      'durationMs': 250,
    },
    'wrong rate': {'pcm': Uint8List(2), 'sampleRate': 48000, 'durationMs': 250},
    'wrong duration type': {
      'pcm': Uint8List(2),
      'sampleRate': 16000,
      'durationMs': 1.5,
    },
    'zero duration': {
      'pcm': Uint8List(2),
      'sampleRate': 16000,
      'durationMs': 0,
    },
    'negative duration': {
      'pcm': Uint8List(2),
      'sampleRate': 16000,
      'durationMs': -1,
    },
    'over duration': {
      'pcm': Uint8List(2),
      'sampleRate': 16000,
      'durationMs': 600001,
    },
    'huge duration': {
      'pcm': Uint8List(2),
      'sampleRate': 16000,
      'durationMs': 1 << 62,
    },
    'missing fields': {},
  };
  for (final entry in cases.entries) {
    test('actual channel rejects ${entry.key}', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => entry.value);
      await expectLater(
        NativePcmDecoderDriver(channel).decode('/private/path'),
        throwsA(generic),
      );
    });
  }
  for (final reply in ['null', 'wrong outer', 'missing plugin', 'platform']) {
    test('actual channel $reply maps generic decoderError', () async {
      if (reply != 'missing plugin') {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              if (reply == 'platform') {
                throw PlatformException(
                  code: 'private-key',
                  message: '/private/path',
                );
              }
              return reply == 'null' ? null : 'private-key';
            });
      }
      await expectLater(
        NativePcmDecoderDriver(channel).decode('/private/path'),
        throwsA(generic),
      );
    });
  }
  for (final size in [
    PcmDecoder.maxOutputBytes,
    PcmDecoder.maxOutputBytes + 2,
  ]) {
    test('actual channel output boundary $size', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {
              'pcm': Uint8List(size),
              'sampleRate': 16000,
              'durationMs': 600000,
            },
          );
      final future = NativePcmDecoderDriver(channel).decode('/private/path');
      if (size > PcmDecoder.maxOutputBytes) {
        await expectLater(future, throwsA(generic));
      } else {
        final result = await future;
        expect(result.bytes.length, size);
        expect(result.duration, PcmDecoder.maxDuration);
      }
    });
  }
  for (final invalid in [
    pcm(size: 0),
    pcm(size: 1),
    pcm(rate: 0),
    pcm(ms: 0),
    pcm(ms: -1),
    pcm(ms: 600001),
    pcm(size: PcmDecoder.maxOutputBytes + 2),
  ]) {
    test(
      'outer driver cannot bypass output validation ${invalid.bytes.length}/${invalid.sampleRate}/${invalid.duration}',
      () async {
        await expectLater(
          PcmDecoder(driver: Driver(() async => invalid)).decode(InputFile()),
          throwsA(generic),
        );
      },
    );
  }
  for (final file in [
    InputFile(present: false),
    InputFile(size: 0),
    InputFile(size: -1),
    InputFile(size: PcmDecoder.maxInputBytes + 1),
    InputFile(fail: 'exists'),
    InputFile(fail: 'length'),
  ]) {
    test(
      'file boundary ${file.present}/${file.size}/${file.fail} never enters driver',
      () async {
        final driver = Driver(() async => pcm());
        await expectLater(
          PcmDecoder(driver: driver).decode(file),
          throwsA(generic),
        );
        expect(driver.calls, 0);
      },
    );
  }
  test('outer exact output cap and duration cap accepted read-only', () async {
    final result = await PcmDecoder(
      driver: Driver(
        () async => pcm(size: PcmDecoder.maxOutputBytes, ms: 600000),
      ),
    ).decode(InputFile());
    expect(result.bytes.length, PcmDecoder.maxOutputBytes);
    expect(result.duration, PcmDecoder.maxDuration);
    expect(() => result.bytes[0] = 1, throwsUnsupportedError);
  });
  test(
    'normal actual channel output is readonly without duration equality',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {
              'pcm': Uint8List.fromList([1, 2]),
              'sampleRate': 16000,
              'durationMs': 250,
            },
          );
      final result = await NativePcmDecoderDriver(channel)
          .decode('/private/path');
      expect(result.bytes, [1, 2]);
      expect(result.duration, const Duration(milliseconds: 250));
      expect(() => result.bytes[0] = 9, throwsUnsupportedError);
    },
  );
  test(
    'entered driver untyped error generic and expected typed error unchanged',
    () async {
      final entered = Completer<void>(), release = Completer<PcmAudio>();
      final driver = Driver(() {
        entered.complete();
        return release.future;
      });
      final future = PcmDecoder(driver: driver).decode(InputFile());
      final checked = expectLater(future, throwsA(generic));
      await entered.future;
      release.completeError(StateError('/private/key'));
      await checked;
      final typed = SttException(SttErrorKind.cancelled, 'cancelled');
      await expectLater(
        PcmDecoder(driver: Driver(() async => throw typed)).decode(InputFile()),
        throwsA(same(typed)),
      );
    },
  );
  test(
    'outer return detached readonly and source duration is independent',
    () async {
      final source = pcm();
      final result = await PcmDecoder(driver: Driver(() async => source))
          .decode(InputFile(size: PcmDecoder.maxInputBytes));
      source.bytes[0] = 255;
      expect(result.bytes, [0, 0]);
      expect(result.duration, const Duration(milliseconds: 250));
      expect(() => result.bytes[0] = 42, throwsUnsupportedError);
    },
  );
}
