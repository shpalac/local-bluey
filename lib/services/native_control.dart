import 'package:flutter/services.dart';

/// A captured view of the Mac's screen: a downscaled JPEG plus the OCR/AX
/// target list the LLM uses to pick what to point at or click.
class ScreenSnapshot {
  const ScreenSnapshot({
    required this.jpeg,
    required this.targets,
    required this.width,
    required this.height,
    this.frontApp,
  });

  /// Downscaled JPEG of the captured region.
  final Uint8List jpeg;

  /// The OCR/accessibility target list the LLM picks from (id, label,
  /// position), in the snapshot's coordinate space.
  final String targets;

  /// Width in display points.
  final double width;

  /// Height in display points.
  final double height;

  /// Bundle/app name that had focus when the snapshot was taken.
  final String? frontApp;
}

/// Dart client for the macOS native bridge (ScreenCaptureKit vision +
/// CGEvent/Accessibility control). Only functional on macOS.
class NativeControl {
  static const MethodChannel _channel = MethodChannel('local_bluey/control');

  /// Whether the app currently holds macOS accessibility permission.
  static Future<bool> isTrusted() async =>
      await _channel.invokeMethod<bool>('isTrusted') ?? false;

  /// Screen-recording preflight; never prompts (#174).
  static Future<bool> screenCaptureAccess() async =>
      await _channel.invokeMethod<bool>('screenCaptureAccess') ?? false;

  /// Registers the app for Screen Recording, prompting the user (#124).
  ///
  /// Preflight is read-only, so an app that only ever calls
  /// [screenCaptureAccess] never shows up under Privacy & Security > Screen
  /// Recording - leaving the recovery card's "Fix" button pointing at an empty
  /// pane. Only call this from an explicit user action.
  static Future<bool> requestScreenCaptureAccess() async =>
      await _channel.invokeMethod<bool>('requestScreenCaptureAccess') ?? false;

  /// Microphone authorization status; never prompts (#174).
  static Future<bool> microphoneAccess() async =>
      await _channel.invokeMethod<bool>('microphoneAccess') ?? false;

  /// Triggers the macOS accessibility permission prompt. No-op when the
  /// permission is already granted.
  static Future<void> askPermission() => _channel.invokeMethod('askPermission');

  /// Opens System Settings on the Accessibility pane.
  static Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod('openAccessibilitySettings');

  /// Current pointer position in display points.
  static Future<Offset> mouseLocation() async {
    final map = await _channel.invokeMapMethod<String, double>('mouseLocation');
    return Offset(map?['x'] ?? 0, map?['y'] ?? 0);
  }

  /// Moves the pointer without pressing a button.
  static Future<void> warp(double x, double y) =>
      _channel.invokeMethod('warp', {'x': x, 'y': y});

  /// Clicks at ([x], [y]). [right] selects the secondary button, [count]
  /// the click count (2 = double click).
  static Future<void> click(
    double x,
    double y, {
    bool right = false,
    int count = 1,
  }) => _channel.invokeMethod('click', {
    'x': x,
    'y': y,
    'right': right,
    'count': count,
  });

  /// Drags from [from] to [to] in one motion.
  static Future<void> drag(Offset from, Offset to) =>
      _channel.invokeMethod('drag', {
        'from': {'x': from.dx, 'y': from.dy},
        'to': {'x': to.dx, 'y': to.dy},
      });

  /// Scrolls at ([x], [y]) by [dx]/[dy] wheel units.
  static Future<void> scroll(double x, double y, {int dx = 0, int dy = 0}) =>
      _channel.invokeMethod('scroll', {'x': x, 'y': y, 'dx': dx, 'dy': dy});

  /// Types [text] as keyboard input.
  static Future<void> type(String text) =>
      _channel.invokeMethod('type', {'text': text});

  /// Presses a key or shortcut like "cmd+t". Returns its label, e.g. "⌘T".
  static Future<String?> press(String combo) =>
      _channel.invokeMethod<String>('press', {'combo': combo});

  /// Opens an application by name. Returns a human-readable result.
  static Future<String?> openApp(String name) =>
      _channel.invokeMethod<String>('openApp', {'name': name});

  /// Opens [url] in the default browser. Returns a human-readable result.
  static Future<String?> openURL(String url) =>
      _channel.invokeMethod<String>('openURL', {'url': url});

  /// Resolves a target id from the last snapshot to screen coordinates.
  /// Ids go stale with their snapshot; capture a fresh one before reusing
  /// an id from an older look.
  static Future<(double, double, String)> resolveTarget(String id) async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'resolveTarget',
      {'id': id},
    );
    return (
      (map?['x'] as num?)?.toDouble() ?? 0,
      (map?['y'] as num?)?.toDouble() ?? 0,
      map?['text'] as String? ?? '',
    );
  }

  /// Cheap watcher signal read (#213): frontmost app, front window title
  /// and lock-screen state. No capture - meant for ~1Hz polling.
  static Future<({String app, String title, bool locked})>
  watchFrontmostInfo() async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'watchFrontmostInfo',
    );
    return (
      app: map?['app'] as String? ?? '',
      title: map?['title'] as String? ?? '',
      locked: map?['locked'] as bool? ?? false,
    );
  }

  /// High-resolution crop of the display, in display points (#80).
  static Future<ScreenSnapshot> snapshotRegion(
    double x,
    double y,
    double width,
    double height,
  ) async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'snapshotRegion',
      {'x': x, 'y': y, 'width': width, 'height': height},
    );
    if (map == null) {
      throw StateError('snapshotRegion returned no data');
    }
    return ScreenSnapshot(
      jpeg: map['jpeg'] as Uint8List,
      targets: map['targets'] as String? ?? '',
      width: (map['width'] as num).toDouble(),
      height: (map['height'] as num).toDouble(),
      frontApp: map['app'] as String? ?? '',
    );
  }

  /// Captures the whole display (downscaled JPEG + target list).
  static Future<ScreenSnapshot> snapshot() async {
    final map = await _channel.invokeMapMethod<String, dynamic>('snapshot');
    if (map == null) {
      throw StateError('snapshot returned no data');
    }
    return ScreenSnapshot(
      jpeg: map['jpeg'] as Uint8List,
      targets: map['targets'] as String? ?? '',
      width: (map['width'] as num?)?.toDouble() ?? 0,
      height: (map['height'] as num?)?.toDouble() ?? 0,
      frontApp: map['app'] as String?,
    );
  }
}
