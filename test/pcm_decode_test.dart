import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/pcm_decode.dart';
import 'package:local_bluey/services/stt.dart';

class FakeDriver implements PcmDecoderDriver {
  FakeDriver({this.result, this.error});

  final PcmAudio? result;
  final Object? error;
  String? lastPath;

  @override
  Future<PcmAudio> decode(String path) async {
    lastPath = path;
    if (error != null) throw error!;
    return result!;
  }
}

PcmAudio samplePcm() => PcmAudio(
  bytes: Uint8List.fromList(List.filled(32000, 1)),
  sampleRate: 16000,
  duration: const Duration(seconds: 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pcm_decode_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<File> writeFile(String name, List<int> bytes) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  group('PcmDecoder (#197 prework)', () {
    test('decodes an existing non-empty file through the driver', () async {
      final f = await writeFile('ok.m4a', [1, 2, 3]);
      final driver = FakeDriver(result: samplePcm());
      final pcm = await PcmDecoder(driver: driver).decode(f);
      expect(pcm.sampleRate, 16000);
      expect(pcm.bytes.length, 32000);
      expect(pcm.duration, const Duration(seconds: 1));
      expect(driver.lastPath, f.path);
    });

    test('missing file throws decoderError', () async {
      final missing = File('${dir.path}/nope.m4a');
      expect(
        () =>
            PcmDecoder(driver: FakeDriver(result: samplePcm())).decode(missing),
        throwsA(
          isA<SttException>().having(
            (e) => e.kind,
            'kind',
            SttErrorKind.decoderError,
          ),
        ),
      );
    });

    test('empty file throws decoderError', () async {
      final f = await writeFile('empty.m4a', const []);
      expect(
        () => PcmDecoder(driver: FakeDriver(result: samplePcm())).decode(f),
        throwsA(
          isA<SttException>().having(
            (e) => e.kind,
            'kind',
            SttErrorKind.decoderError,
          ),
        ),
      );
    });

    test(
      'oversized file throws decoderError before reaching the driver',
      () async {
        final f = await writeFile(
          'big.m4a',
          List.filled(PcmDecoder.maxInputBytes + 1, 0),
        );
        final driver = FakeDriver(result: samplePcm());
        expect(
          () => PcmDecoder(driver: driver).decode(f),
          throwsA(
            isA<SttException>().having(
              (e) => e.kind,
              'kind',
              SttErrorKind.decoderError,
            ),
          ),
        );
        expect(driver.lastPath, isNull);
      },
    );

    test('driver decoderError passes through', () async {
      final f = await writeFile('corrupt.m4a', [0, 0, 0]);
      final driver = FakeDriver(
        error: SttException(SttErrorKind.decoderError, 'corrupt'),
      );
      expect(
        () => PcmDecoder(driver: driver).decode(f),
        throwsA(
          isA<SttException>().having(
            (e) => e.kind,
            'kind',
            SttErrorKind.decoderError,
          ),
        ),
      );
    });
  });

  group('NativePcmDecoderDriver', () {
    const channel = MethodChannel('local_bluey/audio');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('maps a well-formed native reply', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'decodeM4aToPcm');
            expect((call.arguments as Map)['path'], '/tmp/x.m4a');
            return {
              'pcm': Uint8List.fromList([1, 2]),
              'sampleRate': 16000,
              'durationMs': 250,
            };
          });
      final pcm = await NativePcmDecoderDriver(channel).decode('/tmp/x.m4a');
      expect(pcm.sampleRate, 16000);
      expect(pcm.duration, const Duration(milliseconds: 250));
      expect(pcm.bytes, [1, 2]);
    });

    test('PlatformException becomes decoderError', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'decoder_error', message: 'corrupt');
          });
      expect(
        () => NativePcmDecoderDriver(channel).decode('/tmp/x.m4a'),
        throwsA(
          isA<SttException>().having(
            (e) => e.kind,
            'kind',
            SttErrorKind.decoderError,
          ),
        ),
      );
    });

    test('malformed reply becomes decoderError', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return {'unexpected': true};
          });
      expect(
        () => NativePcmDecoderDriver(channel).decode('/tmp/x.m4a'),
        throwsA(
          isA<SttException>().having(
            (e) => e.kind,
            'kind',
            SttErrorKind.decoderError,
          ),
        ),
      );
    });
  });
}
