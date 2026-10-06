import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Pure-Dart frame diff for the watcher (#213): decodes each frame,
/// downsamples to a tiny luma grid and reports the mean absolute
/// difference (0..1) against the previous frame. No frame is kept after
/// the comparison - only the grid survives a tick, and only in memory.
class FrameDiffer {
  static const gridW = 32;
  static const gridH = 18;

  List<double>? _previous;

  /// Difference vs the previous frame; null on the first frame.
  Future<double?> diff(List<int> jpegBytes) async {
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(jpegBytes),
      targetWidth: gridW,
      targetHeight: gridH,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;

    final grid = List<double>.filled(gridW * gridH, 0);
    for (var i = 0; i < gridW * gridH; i++) {
      final o = i * 4;
      grid[i] =
          (0.299 * data.getUint8(o) +
              0.587 * data.getUint8(o + 1) +
              0.114 * data.getUint8(o + 2)) /
          255;
    }

    final previous = _previous;
    _previous = grid;
    if (previous == null) return null;

    var sum = 0.0;
    for (var i = 0; i < grid.length; i++) {
      sum += (grid[i] - previous[i]).abs();
    }
    return sum / grid.length;
  }

  /// Next tick compares against nothing (session ended, app switched).
  void reset() => _previous = null;
}
