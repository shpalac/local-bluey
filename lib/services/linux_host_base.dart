import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

/// Shared plumbing for the Linux host backends (#150 X11, #151 Wayland):
/// helper-binary checks, OCR target formatting and launch commands.
abstract class LinuxHostControlBase implements HostControl {
  LinuxHostControlBase({
    ProcessRunner? run,
    EnvLookup? env,
    Future<bool> Function(String executable)? hasBinary,
    BytesReader? readBytes,
    TempDirMaker? makeTempDir,
  }) : run = run ?? Process.run,
       env = env ?? ((name) => Platform.environment[name]),
       hasBinary = hasBinary ?? defaultHasBinary,
       readBytes = readBytes ?? ((path) => File(path).readAsBytes()),
       makeTempDir = makeTempDir ?? Directory.systemTemp.createTemp;

  /// Process launcher (defaults to [Process.run]).
  final ProcessRunner run;

  /// Environment lookup (defaults to [Platform.environment]).
  final EnvLookup env;

  /// Whether a helper binary exists on PATH.
  final Future<bool> Function(String executable) hasBinary;

  /// File reader for captures.
  final BytesReader readBytes;

  /// Temp-dir factory for intermediate captures.
  final TempDirMaker makeTempDir;

  /// Binary -> apt package, for plain-language missing-helper errors.
  Map<String, String> get requiredTools;

  /// id -> resolved target from the last snapshot, for [resolveTarget].
  final Map<String, ResolvedTarget> lastTargets = {};

  /// Rounds a display-point coordinate to an int (named `num_` to avoid
  /// shadowing the [num] type).
  static int num_(double v) => v.round();

  /// The X11 DISPLAY, or null when none is set (e.g. pure Wayland).
  String? get display {
    final d = env('DISPLAY');
    return (d == null || d.isEmpty) ? null : d;
  }

  /// Lowercased XDG_SESSION_TYPE ('x11', 'wayland', ...), '' when unset.
  String get sessionType => (env('XDG_SESSION_TYPE') ?? '').toLowerCase();

  /// Helper binaries from [requiredTools] that are not on PATH.
  Future<List<String>> missingTools() async {
    final missing = <String>[];
    for (final tool in requiredTools.keys) {
      if (!await hasBinary(tool)) missing.add(tool);
    }
    return missing;
  }

  /// Plain-language install hint for [missing] binaries (apt packages).
  String missingMessage(List<String> missing) {
    final packages = missing.map((t) => requiredTools[t]).toSet().join(' ');
    return 'Linux host control needs: ${missing.join(', ')}. '
        'Install with: sudo apt-get install $packages';
  }

  /// Throws a StateError with the install hint when [tool] is missing.
  Future<void> requireTool(String tool) async {
    if (!await hasBinary(tool)) {
      throw StateError(missingMessage([tool]));
    }
  }

  /// Runs [tool] with [args] and returns stdout. Throws on missing
  /// binary or non-zero exit (stderr included in the message).
  Future<String> stdoutOf(String tool, List<String> args) async {
    await requireTool(tool);
    final result = await run(tool, args);
    if (result.exitCode != 0) {
      throw StateError(
        '$tool ${args.isEmpty ? '' : args.first} failed (exit ${result.exitCode}): '
                '${result.stderr}'
            .trim(),
      );
    }
    return '${result.stdout}';
  }

  /// Like [stdoutOf] when only success/failure matters.
  Future<void> ok(String tool, List<String> args) async {
    await stdoutOf(tool, args);
  }

  /// Exposed for tests: the formatted target list for one capture.
  @visibleForTesting
  Future<String> snapshotTargetsForTest(String imagePath) =>
      ocrTargets(imagePath);

  /// OCRs [imagePath] with tesseract and formats each confident word as a
  /// target line (`W12 @500,300 "text"`), matching the macOS target format
  /// so the ToolExecutor can hand ids back to [resolveTarget].
  Future<String> ocrTargets(String imagePath) async {
    lastTargets.clear();
    if (!await hasBinary('tesseract')) return '';
    final result = await run('tesseract', [imagePath, 'stdout', 'tsv']);
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
      lastTargets[id] = ResolvedTarget(x.toDouble(), y.toDouble(), text);
      buffer.writeln('$id @$x,$y "$text"');
    }
    return buffer.toString().trimRight();
  }

  @override
  Future<ResolvedTarget> resolveTarget(String id) async {
    final target = lastTargets[id];
    if (target == null) {
      throw StateError(
        'Unknown target "$id": take a fresh snapshot and use one of its ids.',
      );
    }
    return target;
  }

  /// Shared post-capture pipeline: downscale to JPEG + OCR targets.
  Future<ScreenSnapshot> buildSnapshot({
    required String rawPngPath,
    required double screenWidth,
    required double screenHeight,
    String? frontApp,
    int maxWidth = 1280,
  }) async {
    final jpg = '$rawPngPath.jpg';
    await ok('convert', [
      rawPngPath,
      '-resize',
      '${maxWidth}x>',
      '-quality',
      '80',
      jpg,
    ]);
    final jpeg = await readBytes(jpg);
    final targets = await ocrTargets(rawPngPath);
    return ScreenSnapshot(
      jpeg: jpeg,
      targets: targets,
      width: screenWidth,
      height: screenHeight,
      frontApp: frontApp,
    );
  }

  @override
  Future<String?> openApp(String name) async {
    // gtk-launch takes a .desktop id; fall back to exec'ing the name.
    if (await hasBinary('gtk-launch')) {
      final result = await run('gtk-launch', [name]);
      if (result.exitCode == 0) return name;
    }
    if (await hasBinary(name)) {
      unawaited(run(name, const []));
      return name;
    }
    throw StateError('No app "$name" found (no .desktop id or binary).');
  }

  @override
  Future<String?> openURL(String url) async {
    await ok('xdg-open', [url]);
    return url;
  }

  @override
  Future<void> openAccessibilitySettings() async {
    // No equivalent on Linux desktops.
  }
}

/// Default `hasBinary` for [LinuxHostControlBase]: true when
/// [executable] resolves on PATH (`which`).
Future<bool> defaultHasBinary(String executable) async {
  try {
    final result = await Process.run('which', [executable]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
