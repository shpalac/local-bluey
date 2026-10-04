import 'dart:convert';
import 'dart:ui' show Offset;

import '../llm/tools.dart';
import 'native_control.dart';

/// The result handed back to the brain after a tool runs.
class ToolResult {
  const ToolResult(this.text, {this.imageBase64});

  final String text;
  final String? imageBase64;
}

/// Executes brain tool calls against the Mac's native layer.
/// Ported from RealtimeHost.runTool / runAction in the original Swift app.
class ToolExecutor {
  ToolExecutor({this._control = const ChannelControl()});

  final NativeControlClient _control;

  /// Screen size from the last look_at_screen, for grid → points conversion.
  double _screenWidth = 0;
  double _screenHeight = 0;
  Offset _home = Offset.zero;
  void Function()? onSleep;

  Offset _grid(double x, double y) =>
      Offset(x / 1000 * _screenWidth, y / 1000 * _screenHeight);

  Future<ToolResult> execute(ToolCall call) async {
    switch (call.name) {
      case 'look_at_screen':
        final snap = await _control.snapshot();
        _screenWidth = snap.width;
        _screenHeight = snap.height;
        _home = await _control.mouseLocation();
        return ToolResult(snap.targets, imageBase64: base64Encode(snap.jpeg));

      case 'point_at':
        final id = call.arguments['target_id'] as String? ?? '';
        final resolved = await _control.resolveTarget(id);
        await _control.warp(resolved.x, resolved.y);
        return ToolResult('Pointing at "$id" (${resolved.text}).');

      case 'point_at_spot':
        final spot = _grid(
          _num(call.arguments['x']),
          _num(call.arguments['y']),
        );
        await _control.warp(spot.dx, spot.dy);
        return ToolResult('Pointing at spot.');

      case 'stop_pointing':
        await _control.warp(_home.dx, _home.dy);
        return ToolResult('Cursor back home.');

      case 'go_to_sleep':
        onSleep?.call();
        return ToolResult('Going to sleep.');

      case 'click':
        final point = await _targetPoint(call.arguments, 'target_id');
        await _control.click(
          point.dx,
          point.dy,
          right: call.arguments['right'] == true,
          count: call.arguments['double'] == true ? 2 : 1,
        );
        return _withScreen('Clicked.');

      case 'type_text':
        await _control.type(call.arguments['text'] as String? ?? '');
        if (call.arguments['press_return'] == true) {
          await _control.press('return');
          return _withScreen('Typed and pressed Return.');
        }
        return ToolResult('Typed.');

      case 'press_keys':
        final label = await _control.press(
          call.arguments['keys'] as String? ?? '',
        );
        return _withScreen('Pressed $label.');

      case 'scroll':
        final direction = call.arguments['direction'] as String? ?? 'down';
        final amount = _num(call.arguments['amount'], fallback: 3) * 120;
        final point = await _targetPointOrCenter(call.arguments);
        final dx = direction == 'left'
            ? -amount
            : (direction == 'right' ? amount : 0);
        final dy = direction == 'up'
            ? -amount
            : (direction == 'down' ? amount : 0);
        await _control.scroll(
          point.dx,
          point.dy,
          dx: dx.round(),
          dy: dy.round(),
        );
        return _withScreen('Scrolled $direction.');

      case 'drag':
        final from = await _targetPoint(
          call.arguments,
          'from_id',
          xKey: 'from_x',
          yKey: 'from_y',
        );
        final to = await _targetPoint(
          call.arguments,
          'to_id',
          xKey: 'to_x',
          yKey: 'to_y',
        );
        await _control.drag(from, to);
        return _withScreen('Dragged.');

      case 'open_app':
        final outcome = await _control.openApp(
          call.arguments['name'] as String? ?? '',
        );
        return _withScreen(outcome ?? '');

      case 'open_url':
        final outcome = await _control.openURL(
          call.arguments['url'] as String? ?? '',
        );
        return _withScreen(outcome ?? '');

      default:
        return ToolResult('Unknown tool ${call.name}.');
    }
  }

  Future<Offset> _targetPoint(
    Map<String, dynamic> args,
    String idKey, {
    String xKey = 'x',
    String yKey = 'y',
  }) async {
    final id = args[idKey] as String?;
    if (id != null && id.isNotEmpty) {
      final resolved = await _control.resolveTarget(id);
      return Offset(resolved.x, resolved.y);
    }
    return _grid(_num(args[xKey]), _num(args[yKey]));
  }

  Future<Offset> _targetPointOrCenter(Map<String, dynamic> args) async {
    final id = args['target_id'] as String?;
    if ((id == null || id.isEmpty) && args['x'] == null) {
      return Offset(_screenWidth / 2, _screenHeight / 2);
    }
    return _targetPoint(args, 'target_id');
  }

  Future<ToolResult> _withScreen(String text) async {
    final snap = await _control.snapshot();
    _screenWidth = snap.width;
    _screenHeight = snap.height;
    return ToolResult(
      '$text\n\n${snap.targets}',
      imageBase64: base64Encode(snap.jpeg),
    );
  }

  double _num(Object? value, {double fallback = 0}) =>
      (value as num?)?.toDouble() ?? fallback;
}

/// Where a resolved target id landed on screen.
class ResolvedTarget {
  const ResolvedTarget(this.x, this.y, this.text);

  final double x;
  final double y;
  final String text;
}

/// The slice of NativeControl the executor needs, so tests can fake it.
abstract class NativeControlClient {
  Future<ScreenSnapshot> snapshot();
  Future<Offset> mouseLocation();
  Future<ResolvedTarget> resolveTarget(String id);
  Future<void> warp(double x, double y);
  Future<void> click(double x, double y, {bool right, int count});
  Future<void> drag(Offset from, Offset to);
  Future<void> scroll(double x, double y, {int dx, int dy});
  Future<void> type(String text);
  Future<String?> press(String combo);
  Future<String?> openApp(String name);
  Future<String?> openURL(String url);
}

/// Live bridge to the macOS MethodChannel via the static [NativeControl] API.
class ChannelControl implements NativeControlClient {
  const ChannelControl();

  @override
  Future<ScreenSnapshot> snapshot() => NativeControl.snapshot();
  @override
  Future<Offset> mouseLocation() => NativeControl.mouseLocation();
  @override
  Future<ResolvedTarget> resolveTarget(String id) async {
    final map = await NativeControl.resolveTarget(id);
    return ResolvedTarget(map.$1, map.$2, map.$3);
  }

  @override
  Future<void> warp(double x, double y) => NativeControl.warp(x, y);
  @override
  Future<void> click(double x, double y, {bool right = false, int count = 1}) =>
      NativeControl.click(x, y, right: right, count: count);
  @override
  Future<void> drag(Offset from, Offset to) => NativeControl.drag(from, to);
  @override
  Future<void> scroll(double x, double y, {int dx = 0, int dy = 0}) =>
      NativeControl.scroll(x, y, dx: dx, dy: dy);
  @override
  Future<void> type(String text) => NativeControl.type(text);
  @override
  Future<String?> press(String combo) => NativeControl.press(combo);
  @override
  Future<String?> openApp(String name) => NativeControl.openApp(name);
  @override
  Future<String?> openURL(String url) => NativeControl.openURL(url);
}
