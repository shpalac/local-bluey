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

  final Uint8List jpeg;
  final String targets;
  final double width;
  final double height;
  final String? frontApp;
}

/// Dart client for the macOS native bridge (ScreenCaptureKit vision +
/// CGEvent/Accessibility control). Only functional on macOS.
class NativeControl {
  static const MethodChannel _channel = MethodChannel('local_bluey/control');

  static Future<bool> isTrusted() async =>
      await _channel.invokeMethod<bool>('isTrusted') ?? false;

  static Future<void> askPermission() => _channel.invokeMethod('askPermission');

  static Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod('openAccessibilitySettings');

  static Future<Offset> mouseLocation() async {
    final map = await _channel.invokeMapMethod<String, double>('mouseLocation');
    return Offset(map?['x'] ?? 0, map?['y'] ?? 0);
  }

  static Future<void> warp(double x, double y) =>
      _channel.invokeMethod('warp', {'x': x, 'y': y});

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

  static Future<void> drag(Offset from, Offset to) =>
      _channel.invokeMethod('drag', {
        'from': {'x': from.dx, 'y': from.dy},
        'to': {'x': to.dx, 'y': to.dy},
      });

  static Future<void> scroll(double x, double y, {int dx = 0, int dy = 0}) =>
      _channel.invokeMethod('scroll', {'x': x, 'y': y, 'dx': dx, 'dy': dy});

  static Future<void> type(String text) =>
      _channel.invokeMethod('type', {'text': text});

  /// Presses a key or shortcut like "cmd+t". Returns its label, e.g. "⌘T".
  static Future<String?> press(String combo) =>
      _channel.invokeMethod<String>('press', {'combo': combo});

  static Future<String?> openApp(String name) =>
      _channel.invokeMethod<String>('openApp', {'name': name});

  static Future<String?> openURL(String url) =>
      _channel.invokeMethod<String>('openURL', {'url': url});

  /// Resolves a target id from the last snapshot to screen coordinates.
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
