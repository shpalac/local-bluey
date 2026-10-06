import 'package:clock/clock.dart';

import 'request_interfaces.dart';

import 'dart:convert';
import 'dart:ui' show Offset;

import '../llm/tools.dart';
import 'action_log.dart';
import 'undo.dart';
import 'native_control.dart';
import 'privacy_guard.dart';

/// The result handed back to the brain after a tool runs.
class ToolResult {
  const ToolResult(this.text, {this.imageBase64});

  /// The text the brain reads as the tool's answer.
  final String text;

  /// Optional screenshot payload (base64 JPEG) for the brain to look at.
  final String? imageBase64;
}

/// Executes brain tool calls against the Mac's native layer.
/// Ported from RealtimeHost.runTool / runAction in the original Swift app.
class ToolExecutor implements ExecutorLike {
  ToolExecutor({
    Clock? clock,
    this._control = const ChannelControl(),
    ActionLog? actionLog,
  }) : _clockOverride = clock,
       _actionLog = actionLog ?? ActionLog.instance;

  /// Injectable clock for tests (#136); falls back to the zone-aware
  /// package:clock so fakeAsync controls time in tests.
  final Clock? _clockOverride;
  Clock get _clock => _clockOverride ?? clock;

  final NativeControlClient _control;
  final ActionLog _actionLog;

  /// Identifies the current brain turn; all its actions share this run id.
  String currentRunId = 'run-0';

  /// Screen size from the last look_at_screen, for grid → points conversion.
  /// Grid coordinates are always 0-1000 on both axes (see kTools docs);
  /// values outside are clamped, and using them before the first snapshot
  /// is an error the brain can correct.
  double _screenWidth = 0;
  double _screenHeight = 0;
  DateTime? _lastSnapshotAt;
  Offset _home = Offset.zero;
  void Function()? onSleep;

  /// Fired after a point_at / point_at_spot actually warped the cursor -
  /// the first-success tutorial listens for it (#176).
  void Function()? onPointed;

  /// The most recent action the host can reverse (#89), exposed so the UI
  /// can offer undo. Null when the last action was final.
  UndoSpec? lastUndoable;

  /// A target id or grid point is only trusted while the snapshot it came
  /// from is fresh. Past this, the brain must look again.
  static const staleAfter = Duration(seconds: 30);

  /// Upper bound for one wait call (#80); longer waits need another call so
  /// each one counts against the turn budget.
  static const maxWaitMs = 5000;

  /// Kill-switch check polled during wait (#80). Wired to SafetyGate.killed
  /// by the host; tests inject their own.
  bool Function() isCancelled = () => false;

  bool get _stale =>
      _lastSnapshotAt == null ||
      _clock.now().difference(_lastSnapshotAt!) > staleAfter;

  String? _stalenessError(Map<String, dynamic> args) {
    final usesTarget = _str(args['target_id']).isNotEmpty;
    final usesGrid = args['x'] != null || args['y'] != null;
    if (!usesTarget && !usesGrid) return null;
    if (_stale) {
      return 'Screen knowledge is stale - call look_at_screen first.';
    }
    return null;
  }

  Offset _grid(double x, double y) {
    final clampedX = x.clamp(0, 1000).toDouble();
    final clampedY = y.clamp(0, 1000).toDouble();
    return Offset(
      clampedX / 1000 * _screenWidth,
      clampedY / 1000 * _screenHeight,
    );
  }

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final ToolResult result;
    try {
      result = await _execute(call);
    } catch (e) {
      // Never leave the brain with an unanswered tool call (#110): a bad
      // argument type or a native failure becomes an Error result the
      // model can react to, and the run continues.
      await _log(call, 'Error: $e', recoveryHint: _recoveryFor(call.name));
      lastUndoable = null;
      return ToolResult('Error: $e');
    }
    final failed = _isFailure(result);
    lastUndoable = failed ? null : undoFor(call.name, call.arguments);
    await _log(
      call,
      result.text.split('\n').first,
      recoveryHint: failed ? _recoveryFor(call.name) : null,
    );
    return result;
  }

  /// Error-text heuristics: results that tell the brain it did something
  /// wrong start with a known marker.
  bool _isFailure(ToolResult result) =>
      result.text.startsWith('Error') ||
      result.text.startsWith('Screen knowledge is stale') ||
      result.text.startsWith('Unknown tool') ||
      result.text.startsWith('No target');

  static String _recoveryFor(String tool) => switch (tool) {
    'click' ||
    'point_at' ||
    'type_text' => 're-look at the screen, then retry with a fresh target',
    'open_app' => 'check the app name against the allowlist',
    'press_keys' => 'check the shortcut label and try again',
    _ => 're-look at the screen and retry',
  };

  Future<void> _log(ToolCall call, String outcome, {String? recoveryHint}) =>
      _actionLog.record(
        ActionEntry(
          runId: currentRunId,
          tool: call.name,
          arguments: call.arguments,
          outcome: outcome,
          recoveryHint: recoveryHint,
        ),
      );

  Future<ToolResult> _execute(ToolCall call) async {
    switch (call.name) {
      case 'look_at_screen':
        final snap = await _control.snapshot();
        _screenWidth = snap.width;
        _screenHeight = snap.height;
        _lastSnapshotAt = _clock.now();
        lastFrontApp = snap.frontApp ?? '';
        _home = await _control.mouseLocation();
        return ToolResult(
          'Display: ${snap.width.toInt()}x${snap.height.toInt()} points.\n'
          '${PrivacyGuard.redact(snap.targets)}',
          imageBase64: _safeImage(snap),
        );

      case 'zoom_screen':
        final staleError = _stalenessError(call.arguments);
        if (staleError != null) return ToolResult(staleError);
        if (_screenWidth == 0) {
          return ToolResult(
            'Screen knowledge is stale - call look_at_screen first.',
          );
        }
        final left =
            _num(call.arguments['x']).clamp(0, 1000) / 1000 * _screenWidth;
        final top =
            _num(call.arguments['y']).clamp(0, 1000) / 1000 * _screenHeight;
        final w =
            _num(call.arguments['width'], fallback: 1000).clamp(1, 1000) /
            1000 *
            _screenWidth;
        final h =
            _num(call.arguments['height'], fallback: 1000).clamp(1, 1000) /
            1000 *
            _screenHeight;
        // Deliberately does not refresh _lastSnapshotAt: the zoom is a
        // detail view of the current snapshot in the same grid, so old
        // target ids keep their original staleness (#80).
        final crop = await _control.snapshotRegion(left, top, w, h);
        // A zoom crop is pixels of the same screen: withhold it when the
        // last snapshot contained sensitive text (#122).
        return ToolResult(
          'Zoomed ${w.toInt()}x${h.toInt()} region at (${left.toInt()},${top.toInt()}) points; coordinates unchanged.',
          imageBase64: PrivacyGuard.hasSensitive(_lastTargets)
              ? null
              : base64Encode(crop.jpeg),
        );

      case 'wait':
        final requested = _num(call.arguments['ms']);
        final ms = requested.clamp(0, maxWaitMs).round();
        final startedAt = _clock.now();
        int elapsed() => _clock.now().difference(startedAt).inMilliseconds;
        while (elapsed() < ms) {
          if (isCancelled()) {
            return ToolResult(
              'Wait cancelled by the kill switch after ${elapsed()} ms.',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        return ToolResult(
          requested > maxWaitMs
              ? 'Waited $ms ms (capped from ${requested.round()}).'
              : 'Waited $ms ms.',
        );

      case 'point_at':
        final staleError = _stalenessError(call.arguments);
        if (staleError != null) return ToolResult(staleError);
        final id = _str(call.arguments['target_id']);
        final resolved = await _control.resolveTarget(id);
        await _control.warp(resolved.x, resolved.y);
        onPointed?.call();
        return ToolResult('Pointing at "$id" (${resolved.text}).');

      case 'point_at_spot':
        final staleError = _stalenessError(call.arguments);
        if (staleError != null) return ToolResult(staleError);
        final spot = _grid(
          _num(call.arguments['x']),
          _num(call.arguments['y']),
        );
        await _control.warp(spot.dx, spot.dy);
        onPointed?.call();
        return ToolResult('Pointing at spot.');

      case 'stop_pointing':
        await _control.warp(_home.dx, _home.dy);
        return ToolResult('Cursor back home.');

      case 'go_to_sleep':
        onSleep?.call();
        return ToolResult('Going to sleep.');

      case 'click':
        final staleError = _stalenessError(call.arguments);
        if (staleError != null) return ToolResult(staleError);
        final point = await _targetPoint(call.arguments, 'target_id');
        await _control.click(
          point.dx,
          point.dy,
          right: call.arguments['right'] == true,
          count: call.arguments['double'] == true ? 2 : 1,
        );
        return _withScreen('Clicked.');

      case 'type_text':
        await _control.type(_str(call.arguments['text']));
        if (call.arguments['press_return'] == true) {
          await _control.press('return');
          return _withScreen('Typed and pressed Return.');
        }
        return ToolResult('Typed.');

      case 'press_keys':
        final label = await _control.press(_str(call.arguments['keys']));
        return _withScreen('Pressed $label.');

      case 'scroll':
        final staleError = _stalenessError(call.arguments);
        if (staleError != null) return ToolResult(staleError);
        final direction = _str(call.arguments['direction'], fallback: 'down');
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
        final staleError = _stalenessError(call.arguments);
        if (staleError != null) return ToolResult(staleError);
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
        final outcome = await _control.openApp(_str(call.arguments['name']));
        return _withScreen(outcome ?? '');

      case 'open_url':
        final outcome = await _control.openURL(_str(call.arguments['url']));
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
    final id = args[idKey] is String ? args[idKey] as String : null;
    if (id != null && id.isNotEmpty) {
      final resolved = await _control.resolveTarget(id);
      return Offset(resolved.x, resolved.y);
    }
    return _grid(_num(args[xKey]), _num(args[yKey]));
  }

  Future<Offset> _targetPointOrCenter(Map<String, dynamic> args) async {
    final id = args['target_id'] is String ? args['target_id'] as String : null;
    if ((id == null || id.isEmpty) && args['x'] == null) {
      return Offset(_screenWidth / 2, _screenHeight / 2);
    }
    return _targetPoint(args, 'target_id');
  }

  /// Front-most app from the last snapshot; the safety gate checks input
  /// tools against it so the allowlist covers more than open_app (#109).
  String lastFrontApp = '';

  Future<ToolResult> _withScreen(String text) async {
    final snap = await _control.snapshot();
    _screenWidth = snap.width;
    _screenHeight = snap.height;
    _lastSnapshotAt = _clock.now();
    lastFrontApp = snap.frontApp ?? '';
    return ToolResult(
      '$text\n\n${PrivacyGuard.redact(snap.targets)}',
      imageBase64: _safeImage(snap),
    );
  }

  /// OCR text of the last snapshot, kept so zoom crops can be withheld
  /// when the screen showed sensitive text (#122).
  String _lastTargets = '';

  /// Returns the base64 screenshot, or null when redaction patterns hit the
  /// OCR text: the pixels would leak the same data the regexes scrub (#122).
  String? _safeImage(ScreenSnapshot snap) {
    _lastTargets = snap.targets;
    if (PrivacyGuard.hasSensitive(snap.targets)) return null;
    return base64Encode(snap.jpeg);
  }

  /// Models often send numbers as strings (#110). Coerce instead of cast.
  double _num(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Same for strings: a model sending {"name": 3} must not throw (#110).
  static String _str(Object? value, {String fallback = ''}) {
    if (value is String) return value;
    return value?.toString() ?? fallback;
  }
}

/// Where a resolved target id landed on screen.
class ResolvedTarget {
  const ResolvedTarget(this.x, this.y, this.text);

  /// Horizontal position in display points.
  final double x;

  /// Vertical position in display points.
  final double y;

  /// The target's label (OCR text or accessibility title).
  final String text;
}

/// The slice of NativeControl the executor needs, so tests can fake it.
abstract class NativeControlClient {
  /// Captures the whole display. Implementations may downscale the JPEG;
  /// coordinates in the result are always in display points.
  Future<ScreenSnapshot> snapshot();

  /// A high-resolution crop of the current display, in display points (#80).
  Future<ScreenSnapshot> snapshotRegion(
    double x,
    double y,
    double width,
    double height,
  );

  /// Current pointer position in display points.
  Future<Offset> mouseLocation();

  /// Resolves a target id to screen coordinates. The id only stays valid
  /// while the snapshot it came from is fresh ([ToolExecutor.staleAfter]);
  /// callers must look again before reusing older ids.
  Future<ResolvedTarget> resolveTarget(String id);

  /// Moves the pointer without pressing a button.
  Future<void> warp(double x, double y);

  /// Clicks at ([x], [y]). [right] selects the secondary button, [count]
  /// the click count (2 = double click).
  Future<void> click(double x, double y, {bool right, int count});

  /// Drags from [from] to [to] in one motion.
  Future<void> drag(Offset from, Offset to);

  /// Scrolls at ([x], [y]) by [dx]/[dy] wheel units.
  Future<void> scroll(double x, double y, {int dx, int dy});

  /// Types [text] as keyboard input. No confirmation happens here; the
  /// safety gate owns that decision.
  Future<void> type(String text);

  /// Presses a key or shortcut like "cmd+t". Returns its display label
  /// (e.g. "⌘T"), or null when the combo is unknown.
  Future<String?> press(String combo);

  /// Opens an application by name. Returns a human-readable result.
  Future<String?> openApp(String name);

  /// Opens [url] in the default browser. Returns a human-readable result.
  Future<String?> openURL(String url);
}

/// Live bridge to the macOS MethodChannel via the static [NativeControl] API.
class ChannelControl implements NativeControlClient {
  const ChannelControl();

  @override
  Future<ScreenSnapshot> snapshot() => NativeControl.snapshot();
  @override
  Future<ScreenSnapshot> snapshotRegion(
    double x,
    double y,
    double width,
    double height,
  ) => NativeControl.snapshotRegion(x, y, width, height);
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
