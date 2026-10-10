import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Owned decoded frame; the differ always releases it after conversion.
abstract interface class DiffImage {
  /// Actual decoded width, not the requested target width.
  int get width;

  /// Actual decoded height, not the requested target height.
  int get height;

  /// RGBA bytes, or null when the conversion is unavailable.
  Future<ByteData?> rgba();

  /// Releases this owned image.
  void dispose();
}

/// Owned codec seam for lifecycle fixtures; production uses dart:ui.
abstract interface class DiffCodec {
  /// Decodes one owned image.
  Future<DiffImage> nextImage();

  /// Releases this owned codec.
  void dispose();
}

/// Creates an owned codec from encoded synthetic/production image bytes.
typedef DiffDecoder = Future<DiffCodec> Function(Uint8List bytes);

class _UiImage implements DiffImage {
  _UiImage(this.image);
  final ui.Image image;
  @override
  int get width => image.width;
  @override
  int get height => image.height;
  @override
  Future<ByteData?> rgba() =>
      image.toByteData(format: ui.ImageByteFormat.rawRgba);
  @override
  void dispose() => image.dispose();
}

class _UiCodec implements DiffCodec {
  _UiCodec(this.codec);
  final ui.Codec codec;
  @override
  Future<DiffImage> nextImage() async =>
      _UiImage((await codec.getNextFrame()).image);
  @override
  void dispose() => codec.dispose();
}

/// Memory-only luma difference (#213). Latest invocation owns the baseline;
/// reset invalidates entered decoding. Stale success/errors return null while
/// current decoder errors and invalid dimensions/bytes propagate. Null byte
/// conversion clears the baseline. Only a grid of at most 32x18 survives.
class FrameDiffer {
  /// Production codec unless a resource fixture decoder is supplied.
  FrameDiffer({DiffDecoder? decoder}) : _decoder = decoder ?? _decode;
  final DiffDecoder _decoder;

  static Future<DiffCodec> _decode(Uint8List bytes) async => _UiCodec(
    await ui.instantiateImageCodec(
      bytes,
      targetWidth: gridW,
      targetHeight: gridH,
      allowUpscaling: false,
    ),
  );

  /// Maximum grid width (cells).
  static const gridW = 32;

  /// Maximum grid height (cells).
  static const gridH = 18;
  List<double>? _previous;
  int? _width, _height;
  int _generation = 0;

  /// Mean difference in 0..1; null for first/current-shape-changed or stale
  /// work. Does not cancel decoder work already entered. Owned resources are
  /// released on every exit, including failures and invalidation.
  Future<double?> diff(List<int> jpegBytes) async {
    final gen = ++_generation;
    bool stale() => gen != _generation;
    DiffCodec? codec;
    DiffImage? image;
    try {
      codec = await _decoder(Uint8List.fromList(jpegBytes));
      if (stale()) return null;
      image = await codec.nextImage();
      if (stale()) return null;
      final width = image.width, height = image.height;
      if (width <= 0 || height <= 0) {
        throw const FormatException('Invalid decoded dimensions');
      }
      final data = await image.rgba();
      if (stale()) return null;
      if (data == null) {
        _clearBaseline();
        return null;
      }
      if (data.lengthInBytes != width * height * 4) {
        throw const FormatException('Invalid decoded RGBA length');
      }
      final cols = width < gridW ? width : gridW;
      final rows = height < gridH ? height : gridH;
      final grid = List<double>.filled(cols * rows, 0);
      for (var y = 0; y < rows; y++) {
        final sourceY = y * height ~/ rows;
        for (var x = 0; x < cols; x++) {
          final o = (sourceY * width + x * width ~/ cols) * 4;
          grid[y * cols + x] =
              (0.299 * data.getUint8(o) +
                  0.587 * data.getUint8(o + 1) +
                  0.114 * data.getUint8(o + 2)) /
              255;
        }
      }
      final previous = _previous;
      final sameShape = _width == width && _height == height;
      _previous = grid;
      _width = width;
      _height = height;
      if (previous == null || !sameShape) return null;
      var sum = 0.0;
      for (var i = 0; i < grid.length; i++) {
        sum += (grid[i] - previous[i]).abs();
      }
      return (sum / grid.length).clamp(0.0, 1.0);
    } catch (_) {
      if (stale()) return null;
      _clearBaseline();
      rethrow;
    } finally {
      // Codec still releases if image cleanup itself reports a failure.
      try {
        image?.dispose();
      } finally {
        codec?.dispose();
      }
    }
  }

  void _clearBaseline() {
    _previous = null;
    _width = _height = null;
  }

  /// Invalidates entered work; the next current frame is a fresh baseline.
  void reset() {
    _generation++;
    _clearBaseline();
  }
}
