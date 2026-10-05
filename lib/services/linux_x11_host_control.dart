import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'host_control.dart';
import 'native_control.dart';
import 'tool_executor.dart';

/// Runs a process and returns its result. Injectable for tests.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Looks up an environment variable. Injectable for tests.
typedef EnvLookup = String? Function(String name);

/// Reads a file's bytes. Injectable for tests.
typedef BytesReader = Future<Uint8List> Function(String path);

/// Creates a temp directory. Injectable for tests.
typedef TempDirMaker = Future<Directory> Function();

/// X11 host control (#150): drives the desktop through helper binaries
/// (xdotool, ImageMagick, tesseract, xdg-open) instead of a native plugin.
/// Every invocation passes an argv array to [Process.run] - arguments are
/// never shell-interpolated.
///
/// Limits: X11 sessions only. Wayland needs xdg-desktop-portal (#151).
class LinuxX11HostControl implements HostControl {
  LinuxX11HostControl({
    ProcessRunner? run,
    EnvLookup? env,
    Future<bool> Function(String executable)? hasBinary,
    BytesReader? readBytes,
    TempDirMaker? makeTempDir,
  }) : _run = run ?? Process.run,
       _env = env ?? ((name) => Platform.environment[name]),
       _hasBinary = hasBinary ?? _defaultHasBinary,
       _readBytes = readBytes ?? ((path) => File(path).readAsBytes()),
       _makeTempDir = makeTempDir ?? Directory.systemTemp.createTemp;

  final ProcessRunner _run;
  final EnvLookup _env;
  final Future<bool> Function(String executable) _hasBinary;
  final BytesReader _readBytes;
  final TempDirMaker _makeTempDir;

  /// Helper binaries each capability needs. Missing ones surface as a
  /// plain-language [StateError] naming the package to install.
  static const _captureTools = {
    'import': 'imagemagick',
    'convert': 'imagemagick',
  };
  static const _inputTools = {'xdotool': 'xdotool'};
  static const _ocrTools = {'tesseract': 'tesseract'};
  static const _launchTools = {
    'xdg-open': 'xdg-utils',
    'gtk-launch': 'libgtk-3-bin',
  };

  static final _allTools = {
    ..._captureTools,
    ..._inputTools,
    ..._ocrTools,
    ..._launchTools,
  };

  /// id -> resolved target from the last [snapshot], for [resolveTarget].
  final Map<String, ResolvedTarget> _lastTargets = {};

  String? get _display {
    final display = _env('DISPLAY');
    return (display == null || display.isEmpty) ? null : display;
  }

  /// True when this looks like a Wayland-only session (#151 covers it).
  bool get isWaylandSession =>
      (_env('XDG_SESSION_TYPE') ?? '').toLowerCase() == 'wayland' &&
      _display == null;

  @override
  Future<bool> isTrusted() async {
    // X11 has no permission prompt: access is whoever owns the display.
    // "Trusted" therefore means "capable": a display plus the helpers.
    if (_display == null) return false;
    for (final tool in _allTools.keys) {
      if (!await _hasBinary(tool)) return false;
    }
    return true;
  }

  @override
  Future<void> askPermission() async {
    // Nothing to grant on X11; fail loudly if the host is not capable.
    if (await isTrusted()) return;
    throw StateError(_missingMessage(await _missingTools()));
  }

  @override
  Future<void> openAccessibilitySettings() async {
    // No equivalent on X11 - input injection needs no toggle.
  }

  Future<List<String>> _missingTools() async {
    final missing = <String>[];
    for (final tool in _allTools.keys) {
      if (!await _hasBinary(tool)) missing.add(tool);
    }
    return missing;
  }

  String _missingMessage(List<String> missing) {
    final packages = missing.map((t) => _allTools[t]).toSet().join(' ');
    return 'Linux host control needs: ${missing.join(', ')}. '
        'Install with: sudo apt-get install $packages';
  }

  Future<void> _require(String tool) async {
    if (!await _hasBinary(tool)) {
      throw StateError(_missingMessage([tool]));
    }
  }

  Future<String> _stdout(String tool, List<String> args) async {
    await _require(tool);
    final result = await _run(tool, args);
    if (result.exitCode != 0) {
      throw StateError(
        '$tool ${args.first} failed (exit ${result.exitCode}): '
                '${result.stderr}'
            .trim(),
      );
    }
    return '${result.stdout}';
  }

  Future<void> _ok(String tool, List<String> args) async {
    await _stdout(tool, args);
  }

  Future<(double, double)> _displaySize() async {
    final out = await _stdout('xdotool', ['getdisplaygeometry']);
    final parts = out.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) {
      throw StateError('unexpected getdisplaygeometry output: $out');
    }
    return (double.parse(parts[0]), double.parse(parts[1]));
  }

  static int _num(double v) => v.round();

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
      region: '${_num(width)}x${_num(height)}+${_num(x)}+${_num(y)}',
      screenWidth: w,
      screenHeight: h,
    );
  }

  Future<ScreenSnapshot> _capture({
    required String? region,
    required double screenWidth,
    required double screenHeight,
  }) async {
    final dir = await _makeTempDir();
    try {
      final raw = '${dir.path}/shot.png';
      final jpg = '${dir.path}/shot.jpg';
      final args = ['-window', 'root'];
      if (region != null) args.addAll(['-crop', region]);
      args.add(raw);
      await _ok('import', args);

      // Downscale like the macOS bridge so the LLM gets a light image.
      const maxWidth = 1280;
      await _ok('convert', [
        raw,
        '-resize',
        '${maxWidth}x>',
        '-quality',
        '80',
        jpg,
      ]);
      final jpeg = await _readBytes(jpg);

      final targets = await _ocrTargets(raw);
      final app = await _frontApp();
      return ScreenSnapshot(
        jpeg: jpeg,
        targets: targets,
        width: screenWidth,
        height: screenHeight,
        frontApp: app,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// OCRs [imagePath] with tesseract and formats each confident word as a
  /// target line (`W12 @500,300 "text"`), matching the macOS target format
  /// so the ToolExecutor can hand ids back to [resolveTarget].
  /// Exposed for tests: the formatted target list for one capture.
  @visibleForTesting
  Future<String> snapshotTargetsForTest(String imagePath) =>
      _ocrTargets(imagePath);

  Future<String> _ocrTargets(String imagePath) async {
    _lastTargets.clear();
    if (!await _hasBinary('tesseract')) return '';
    final result = await _run('tesseract', [imagePath, 'stdout', 'tsv']);
    if (result.exitCode != 0) return '';
    final lines = const LineSplitter().convert('${result.stdout}');
    final buffer = StringBuffer();
    var index = 0;
    for (final line in lines.skip(1)) {
      final cols = line.split('\t');
      if (cols.length != 12) continue;
      final text = cols[11].trim();
      final conf = double.tryParse(cols[10]) ?? -1;
      if (text.isEmpty || conf < 40) continue;
      final x = (double.parse(cols[6]) + double.parse(cols[8]) / 2).round();
      final y = (double.parse(cols[7]) + double.parse(cols[9]) / 2).round();
      index++;
      final id = 'W$index';
      _lastTargets[id] = ResolvedTarget(x.toDouble(), y.toDouble(), text);
      buffer.writeln('$id @$x,$y "$text"');
    }
    return buffer.toString().trimRight();
  }

  Future<String?> _frontApp() async {
    try {
      final win = await _stdout('xdotool', ['getactivewindow']);
      return (await _stdout('xdotool', ['getwindowname', win.trim()])).trim();
    } on StateError {
      return null;
    }
  }

  @override
  Future<Offset> mouseLocation() async {
    final out = await _stdout('xdotool', ['getmouselocation', '--shell']);
    double read(String key) {
      final match = RegExp('^$key=(.+)\$', multiLine: true).firstMatch(out);
      return double.tryParse(match?.group(1) ?? '') ?? 0;
    }

    return Offset(read('X'), read('Y'));
  }

  @override
  Future<ResolvedTarget> resolveTarget(String id) async {
    final target = _lastTargets[id];
    if (target == null) {
      throw StateError(
        'Unknown target "$id": take a fresh snapshot and use one of its ids.',
      );
    }
    return target;
  }

  @override
  Future<void> warp(double x, double y) =>
      _ok('xdotool', ['mousemove', '${_num(x)}', '${_num(y)}']);

  @override
  Future<void> click(
    double x,
    double y, {
    bool right = false,
    int count = 1,
  }) async {
    await warp(x, y);
    await _ok('xdotool', ['click', '--repeat', '$count', right ? '3' : '1']);
  }

  @override
  Future<void> drag(Offset from, Offset to) async {
    await warp(from.dx, from.dy);
    await _ok('xdotool', ['mousedown', '1']);
    await _ok('xdotool', ['mousemove', '${_num(to.dx)}', '${_num(to.dy)}']);
    await _ok('xdotool', ['mouseup', '1']);
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
    await _ok('xdotool', ['click', '--repeat', '$clicks', button]);
  }

  @override
  Future<void> type(String text) =>
      _ok('xdotool', ['type', '--clearmodifiers', '--', text]);

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
    await _ok('xdotool', ['key', '--clearmodifiers', keys]);
    return keys;
  }

  @override
  Future<String?> openApp(String name) async {
    // gtk-launch takes a .desktop id; fall back to exec'ing the name.
    if (await _hasBinary('gtk-launch')) {
      final result = await _run('gtk-launch', [name]);
      if (result.exitCode == 0) return name;
    }
    if (await _hasBinary(name)) {
      unawaited(_run(name, const []));
      return name;
    }
    throw StateError('No app "$name" found (no .desktop id or binary).');
  }

  @override
  Future<String?> openURL(String url) async {
    await _ok('xdg-open', [url]);
    return url;
  }
}

Future<bool> _defaultHasBinary(String executable) async {
  try {
    final result = await Process.run('which', [executable]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
