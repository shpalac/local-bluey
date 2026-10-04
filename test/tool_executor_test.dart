import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/tools.dart';
import 'package:local_bluey/services/native_control.dart';
import 'package:local_bluey/services/tool_executor.dart';

void main() {
  late FakeControl control;
  late ToolExecutor executor;

  setUp(() {
    control = FakeControl();
    executor = ToolExecutor(control: control);
  });

  test('look_at_screen captures and returns targets + image', () async {
    final result = await executor.execute(ToolCall('look_at_screen', {}));
    expect(control.snapshots, 1);
    expect(result.text, contains('L1'));
    expect(result.imageBase64, isNotEmpty);
  });

  test('point_at resolves the id natively and warps there', () async {
    await executor.execute(ToolCall('look_at_screen', {}));
    await executor.execute(ToolCall('point_at', {'target_id': 'W12'}));
    expect(control.lastWarp, const Offset(500, 300));
  });

  test('click converts 0-1000 grid to screen points', () async {
    await executor.execute(ToolCall('look_at_screen', {})); // 2000x1000 fake
    await executor.execute(ToolCall('click', {'x': 500, 'y': 300}));
    expect(control.clicks.single.$1, const Offset(1000, 300));
  });

  test('click prefers target id over grid', () async {
    await executor.execute(ToolCall('look_at_screen', {}));
    await executor.execute(
      ToolCall('click', {'target_id': 'C4', 'x': 500, 'y': 300}),
    );
    expect(control.clicks.single.$1, const Offset(500, 300));
  });

  test('go_to_sleep fires the callback', () async {
    var slept = false;
    executor.onSleep = () => slept = true;
    await executor.execute(ToolCall('go_to_sleep', {}));
    expect(slept, isTrue);
  });

  test('press_keys returns a fresh screen afterwards', () async {
    await executor.execute(ToolCall('look_at_screen', {}));
    final result = await executor.execute(
      ToolCall('press_keys', {'keys': 'cmd+t'}),
    );
    expect(control.presses, ['cmd+t']);
    expect(result.text, contains('Pressed'));
    expect(result.imageBase64, isNotEmpty);
    expect(control.snapshots, 2);
  });
}

class FakeControl implements NativeControlClient {
  int snapshots = 0;
  Offset? lastWarp;
  final clicks = <(Offset, bool, int)>[];
  final presses = <String>[];

  static const _jpeg = [1, 2, 3];

  @override
  Future<ScreenSnapshot> snapshot() async {
    snapshots++;
    return ScreenSnapshot(
      jpeg: Uint8List.fromList(_jpeg),
      targets: 'L1 @500,12 "Hello"',
      width: 2000,
      height: 1000,
      frontApp: 'Safari',
    );
  }

  @override
  Future<Offset> mouseLocation() async => const Offset(42, 42);

  @override
  Future<ResolvedTarget> resolveTarget(String id) async =>
      const ResolvedTarget(500, 300, 'OK');

  @override
  Future<void> warp(double x, double y) async => lastWarp = Offset(x, y);

  @override
  Future<void> click(
    double x,
    double y, {
    bool right = false,
    int count = 1,
  }) async => clicks.add((Offset(x, y), right, count));

  @override
  Future<void> drag(Offset from, Offset to) async {}

  @override
  Future<void> scroll(double x, double y, {int dx = 0, int dy = 0}) async {}

  @override
  Future<void> type(String text) async {}

  @override
  Future<String?> press(String combo) async {
    presses.add(combo);
    return '⌘T';
  }

  @override
  Future<String?> openApp(String name) async => 'Opened $name.';

  @override
  Future<String?> openURL(String url) async => 'Opened $url.';
}
