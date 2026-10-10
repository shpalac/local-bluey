import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/frame_differ.dart';

class ImageFixture implements DiffImage {
  ImageFixture({this.width = 2, this.height = 2, this.value = 0, this.bytes});
  @override
  final int width;
  @override
  final int height;
  final int value;
  Future<ByteData?> Function()? bytes;
  int releases = 0;
  @override
  Future<ByteData?> rgba() async => bytes != null
      ? bytes!()
      : ByteData.sublistView(
          Uint8List.fromList(List.filled(width * height * 4, value)),
        );
  @override
  void dispose() {
    releases++;
  }
}

class CodecFixture implements DiffCodec {
  CodecFixture(this.image, {this.frame});
  final ImageFixture image;
  Future<DiffImage> Function()? frame;
  int releases = 0;
  @override
  Future<DiffImage> nextImage() async => frame != null ? frame!() : image;
  @override
  void dispose() {
    releases++;
  }
}

Future<Uint8List> png(int width, int height, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [(1, 1), (3, 2), (32, 18), (120, 1), (1, 120), (80, 60)]) {
    test(
      'synthetic production codec ${size.$1}x${size.$2} stable and changed pixels',
      () async {
        final black = await png(size.$1, size.$2, const ui.Color(0xff000000));
        final white = await png(size.$1, size.$2, const ui.Color(0xffffffff));
        final red = await png(size.$1, size.$2, const ui.Color(0xffff0000));
        final differ = FrameDiffer();
        expect(await differ.diff(black), isNull);
        expect(await differ.diff(black), closeTo(0, 0.001));
        expect(await differ.diff(white), closeTo(1, 0.001));
        differ.reset();
        expect(await differ.diff(black), isNull);
        expect(await differ.diff(red), closeTo(0.299, 0.01));
      },
    );
  }
  test(
    'production malformed input throws and next good input baseline fresh',
    () async {
      final differ = FrameDiffer();
      final black = await png(2, 2, const ui.Color(0xff000000));
      await differ.diff(black);
      await expectLater(differ.diff([0, 1, 2]), throwsA(anything));
      expect(await differ.diff(black), isNull);
    },
  );
  for (final stage in ['decode', 'frame', 'bytes']) {
    for (final error in [false, true]) {
      test(
        'reset entered $stage ${error ? "error" : "success"} releases and stays fresh',
        () async {
          final entered = Completer<void>(), release = Completer<void>();
          final image = ImageFixture(), codec = CodecFixture(ImageFixture());
          codec.frame = () async {
            if (stage == 'frame') {
              entered.complete();
              await release.future;
              if (error) throw StateError('frame');
            }
            return image;
          };
          image.bytes = () async {
            if (stage == 'bytes') {
              entered.complete();
              await release.future;
              if (error) throw StateError('bytes');
            }
            return ByteData(16);
          };
          var first = true;
          final differ = FrameDiffer(
            decoder: (_) async {
              if (!first) return CodecFixture(ImageFixture());
              first = false;
              if (stage == 'decode') {
                entered.complete();
                await release.future;
                if (error) throw StateError('decode');
              }
              return codec;
            },
          );
          final pending = differ.diff([0]);
          await entered.future;
          differ.reset();
          release.complete();
          expect(await pending, isNull);
          expect(codec.releases, stage == 'decode' && error ? 0 : 1);
          expect(
            image.releases,
            stage == 'decode' || (stage == 'frame' && error) ? 0 : 1,
          );
          expect(await differ.diff([0]), isNull);
          expect(await differ.diff([0]), 0);
        },
      );
    }
  }
  test(
    'latest concurrent completion owns baseline; old work released',
    () async {
      final release = Completer<void>(), entered = Completer<void>();
      final old = ImageFixture(value: 0), latest = ImageFixture(value: 255);
      final codecs = <CodecFixture>[];
      var calls = 0;
      final differ = FrameDiffer(
        decoder: (_) async {
          final codec = CodecFixture(calls++ == 0 ? old : latest);
          codecs.add(codec);
          if (calls == 1) {
            entered.complete();
            await release.future;
          }
          return codec;
        },
      );
      final first = differ.diff([0]);
      await entered.future;
      expect(await differ.diff([1]), isNull);
      release.complete();
      expect(await first, isNull);
      expect(await differ.diff([2]), 0);
      expect(old.releases, 0);
      expect(codecs.first.releases, 1);
    },
  );
  test('shape change baseline; malformed dimensions/bytes and null conversion clear', () async {
    final images = [
      ImageFixture(),
      ImageFixture(width: 1, height: 4),
      ImageFixture(width: 0),
      ImageFixture(bytes: () async => ByteData(2)),
      ImageFixture(bytes: () async => null),
      ImageFixture(),
    ];
    final codecs = <CodecFixture>[];
    final differ = FrameDiffer(
      decoder: (_) async {
        final c = CodecFixture(images[codecs.length]);
        codecs.add(c);
        return c;
      },
    );
    expect(await differ.diff([0]), isNull);
    expect(await differ.diff([0]), isNull);
    await expectLater(differ.diff([0]), throwsFormatException);
    await expectLater(differ.diff([0]), throwsFormatException);
    expect(await differ.diff([0]), isNull);
    expect(await differ.diff([0]), isNull);
    expect(codecs.every((c) => c.releases == 1), isTrue);
    expect(images.every((i) => i.releases == 1), isTrue);
  });
  for (final stage in ['frame', 'bytes']) {
    test(
      'current $stage error propagates and acquired resources released',
      () async {
        final image = ImageFixture();
        final codec = CodecFixture(image);
        if (stage == 'frame') {
          codec.frame = () async => throw StateError('frame');
        } else {
          image.bytes = () async => throw StateError('bytes');
        }
        final differ = FrameDiffer(decoder: (_) async => codec);
        await expectLater(differ.diff([0]), throwsStateError);
        expect(codec.releases, 1);
        expect(image.releases, stage == 'frame' ? 0 : 1);
      },
    );
  }
  for (final stage in ['frame', 'bytes']) {
    test(
      'out-of-order $stage completion cannot replace newest baseline',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final old = ImageFixture(value: 0),
            oldCodec = CodecFixture(ImageFixture());
        oldCodec.frame = () async {
          if (stage == 'frame') {
            entered.complete();
            await release.future;
          }
          return old;
        };
        old.bytes = () async {
          if (stage == 'bytes') {
            entered.complete();
            await release.future;
          }
          return ByteData(16);
        };
        var calls = 0;
        final fresh = <CodecFixture>[];
        final differ = FrameDiffer(
          decoder: (_) async {
            if (calls++ == 0) return oldCodec;
            final c = CodecFixture(ImageFixture(value: 255));
            fresh.add(c);
            return c;
          },
        );
        final pending = differ.diff([0]);
        await entered.future;
        expect(await differ.diff([1]), isNull);
        release.complete();
        expect(await pending, isNull);
        expect(await differ.diff([1]), 0);
        expect(old.releases, 1);
        expect(oldCodec.releases, 1);
        expect(
          fresh.every((c) => c.releases == 1 && c.image.releases == 1),
          isTrue,
        );
      },
    );
  }
}
