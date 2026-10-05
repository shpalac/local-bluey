import 'dart:ui' show Offset;

import 'linux_host_base.dart';
import 'native_control.dart';

/// X11 host control (#150): drives the desktop through helper binaries
/// (xdotool, ImageMagick, tesseract, xdg-open) instead of a native plugin.
/// Every invocation passes an argv array to [Process.run] - arguments are
/// never shell-interpolated.
///
/// Limits: X11 sessions only. Wayland needs xdg-desktop-portal (#151).
class LinuxX11HostControl extends LinuxHostControlBase {
  LinuxX11HostControl({
    super.run,
    super.env,
    super.hasBinary,
    super.readBytes,
    super.makeTempDir,
  });

  /// Helper binaries each capability needs. Missing ones surface as a
  /// plain-language [StateError] naming the package to install.
  static const _tools = {
    'import': 'imagemagick',
    'convert': 'imagemagick',
    'xdotool': 'xdotool',
    'tesseract': 'tesseract',
    'xdg-open': 'xdg-utils',
    'gtk-launch': 'libgtk-3-bin',
  };

  @override
  Map<String, String> get requiredTools => _tools;

  /// True when this looks like a Wayland-only session (#151 covers it).
  bool get isWaylandSession => sessionType == 'wayland' && display == null;

  @override
  Future<bool> isTrusted() async {
    // X11 has no permission prompt: access is whoever owns the display.
    // "Trusted" therefore means "capable": a display plus the helpers.
    if (display == null) return false;
    for (final tool in _tools.keys) {
      if (!await hasBinary(tool)) return false;
    }
    return true;
  }

  @override
  Future<void> askPermission() async {
    // Nothing to grant on X11; fail loudly if the host is not capable.
    if (await isTrusted()) return;
    throw StateError(missingMessage(await missingTools()));
  }

  Future<(double, double)> _displaySize() async {
    final out = await stdoutOf('xdotool', ['getdisplaygeometry']);
    final parts = out.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) {
      throw StateError('unexpected getdisplaygeometry output: $out');
    }
    return (double.parse(parts[0]), double.parse(parts[1]));
  }

  @override
  Future<ScreenSnapshot> snapshot() async {
    final (w, h) = await _displaySize();
    return _capture(region: null, screenWidth: w, screenHeight: h);
  }

  @override
  Future<ScreenSnapshot> snapshotRegion(
    double x,
    double y,
    double width,
    double height,
  ) async {
    final (w, h) = await _displaySize();
    return _capture(
      region:
          '${LinuxHostControlBase.num_(width)}x${LinuxHostControlBase.num_(height)}'
          '+${LinuxHostControlBase.num_(x)}+${LinuxHostControlBase.num_(y)}',
      screenWidth: w,
      screenHeight: h,
    );
  }

  Future<ScreenSnapshot> _capture({
    required String? region,
    required double screenWidth,
    required double screenHeight,
  }) async {
    final dir = await makeTempDir();
    try {
      final raw = '${dir.path}/shot.png';
      final args = ['-window', 'root'];
      if (region != null) args.addAll(['-crop', region]);
      args.add(raw);
      await ok('import', args);
      final app = await _frontApp();
      return await buildSnapshot(
        rawPngPath: raw,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
        frontApp: app,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }

  Future<String?> _frontApp() async {
    try {
      final win = await stdoutOf('xdotool', ['getactivewindow']);
      return (await stdoutOf('xdotool', ['getwindowname', win.trim()])).trim();
    } on StateError {
      return null;
    }
  }

  @override
  Future<Offset> mouseLocation() async {
    final out = await stdoutOf('xdotool', ['getmouselocation', '--shell']);
    double read(String key) {
      final match = RegExp('^$key=(.+)\$', multiLine: true).firstMatch(out);
      return double.tryParse(match?.group(1) ?? '') ?? 0;
    }

    return Offset(read('X'), read('Y'));
  }

  @override
  Future<void> warp(double x, double y) => ok('xdotool', [
    'mousemove',
    '${LinuxHostControlBase.num_(x)}',
    '${LinuxHostControlBase.num_(y)}',
  ]);

  @override
  Future<void> click(
    double x,
    double y, {
    bool right = false,
    int count = 1,
  }) async {
    await warp(x, y);
    await ok('xdotool', ['click', '--repeat', '$count', right ? '3' : '1']);
  }

  @override
  Future<void> drag(Offset from, Offset to) async {
    await warp(from.dx, from.dy);
    await ok('xdotool', ['mousedown', '1']);
    await ok('xdotool', [
      'mousemove',
      '${LinuxHostControlBase.num_(to.dx)}',
      '${LinuxHostControlBase.num_(to.dy)}',
    ]);
    await ok('xdotool', ['mouseup', '1']);
  }

  @override
  Future<void> scroll(double x, double y, {int dx = 0, int dy = 0}) async {
    await warp(x, y);
    // X11 buttons: 4 up, 5 down, 6 left, 7 right.
    final button = dy < 0
        ? '4'
        : dy > 0
        ? '5'
        : dx < 0
        ? '6'
        : '7';
    final clicks = (dy != 0 ? dy.abs() : dx.abs()).clamp(1, 50);
    await ok('xdotool', ['click', '--repeat', '$clicks', button]);
  }

  @override
  Future<void> type(String text) =>
      ok('xdotool', ['type', '--clearmodifiers', '--', text]);

  /// Maps a combo like "cmd+t" to xdotool key syntax and presses it.
  /// macOS names are translated: cmd->super, option->alt.
  @override
  Future<String?> press(String combo) async {
    final keys = combo
        .split('+')
        .map((k) => k.trim().toLowerCase())
        .map((k) {
          return switch (k) {
            'cmd' || 'meta' || 'win' => 'super',
            'option' => 'alt',
            'return' => 'enter',
            'esc' => 'escape',
            _ => k,
          };
        })
        .join('+');
    if (keys.isEmpty) return null;
    await ok('xdotool', ['key', '--clearmodifiers', keys]);
    return keys;
  }
}
