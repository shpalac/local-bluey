import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
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

  test('sensitive OCR text withholds the screenshot (#122)', () async {
    control.snapshotTargets = 'card 4111 1111 1111 1111';
    final result = await executor.execute(ToolCall('look_at_screen', {}));
    expect(result.text, contains('[redacted]'));
    expect(result.text, isNot(contains('4111')));
    expect(result.imageBase64, isNull);
  });

  test('zoom crop is withheld after a sensitive snapshot (#122)', () async {
    control.snapshotTargets = 'user@example.com';
    await executor.execute(ToolCall('look_at_screen', {}));
    final zoom = await executor.execute(
      ToolCall('zoom_screen', {'x': 0, 'y': 0, 'width': 500, 'height': 500}),
    );
    expect(zoom.imageBase64, isNull);
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

  test('zoom_screen maps the grid region to display points (#80)', () async {
    await executor.execute(ToolCall('look_at_screen', {})); // 2000x1000 fake
    final result = await executor.execute(
      ToolCall('zoom_screen', {'x': 500, 'y': 0, 'width': 250, 'height': 500}),
    );
    expect(control.lastRegion, (1000.0, 0.0, 500.0, 500.0));
    expect(result.text, contains('coordinates unchanged'));
    expect(result.imageBase64, isNotEmpty);
  });

  test('zoom round-trips on a different display size (#80)', () async {
    control.screenSize = (3008, 1692);
    await executor.execute(ToolCall('look_at_screen', {}));
    await executor.execute(
      ToolCall('zoom_screen', {
        'x': 250,
        'y': 250,
        'width': 500,
        'height': 500,
      }),
    );
    expect(control.lastRegion, (752.0, 423.0, 1504.0, 846.0));
  });

  test('zoom requires a fresh snapshot', () async {
    final result = await executor.execute(
      ToolCall('zoom_screen', {'x': 0, 'y': 0, 'width': 100, 'height': 100}),
    );
    expect(result.text, contains('look_at_screen'));
  });

  test('a stale target is still rejected after a zoom (#80)', () {
    // Fake time: no wall-clock wait for staleness (#136).
    fakeAsync((async) {
      executor.execute(ToolCall('look_at_screen', {}));
      executor.execute(
        ToolCall('zoom_screen', {'x': 0, 'y': 0, 'width': 100, 'height': 100}),
      );
      async.elapse(ToolExecutor.staleAfter + const Duration(seconds: 1));
      executor
          .execute(ToolCall('click', {'target_id': 'C4'}))
          .then((result) => expect(result.text, contains('stale')));
      async.flushMicrotasks();
    });
  });

  test('wait is bounded at the maximum (#80)', () async {
    final result = await executor.execute(ToolCall('wait', {'ms': 99999}));
    expect(result.text, contains('capped'));
    expect(result.text, contains('${ToolExecutor.maxWaitMs}'));
  });

  test('wait is cancelled by the kill switch (#80)', () {
    // Fake time: the 3 s wait costs no wall-clock time (#136).
    fakeAsync((async) {
      var killed = false;
      executor.isCancelled = () => killed;
      final pending = executor.execute(ToolCall('wait', {'ms': 3000}));
      async.elapse(const Duration(milliseconds: 120));
      killed = true;
      async.elapse(const Duration(seconds: 3));
      pending.then((result) => expect(result.text, contains('cancelled')));
      async.flushMicrotasks();
    });
  });
  group('#110: bad arguments become Error results, not aborts', () {
    test('numbers sent as strings are coerced', () async {
      await executor.execute(ToolCall('look_at_screen', {}));
      final result = await executor.execute(
        ToolCall('click', {'x': '500', 'y': '300'}),
      );
      expect(result.text, isNot(startsWith('Error')));
      expect(control.clicks.single.$1, const Offset(1000, 300));
    });

    test('non-string text does not throw and reaches the brain', () async {
      final result = await executor.execute(
        ToolCall('type_text', {'text': 42}),
      );
      expect(result.text, isNot(startsWith('Error')));
    });

    test(
      'native failure returns an Error result instead of rethrowing',
      () async {
        control.throwOnSnapshot = true;
        final result = await executor.execute(ToolCall('look_at_screen', {}));
        expect(result.text, startsWith('Error'));
      },
    );
  });
}

class FakeControl implements NativeControlClient {
  int snapshots = 0;
  Offset? lastWarp;
  final clicks = <(Offset, bool, int)>[];
  final presses = <String>[];

  static const _jpeg = [1, 2, 3];
  bool throwOnSnapshot = false;

  (double, double) screenSize = (2000, 1000);
  String snapshotTargets = 'L1 @500,12 "Hello"';

  @override
  Future<ScreenSnapshot> snapshot() async {
    if (throwOnSnapshot) throw StateError('native snapshot failed');
    snapshots++;
    return ScreenSnapshot(
      jpeg: Uint8List.fromList(_jpeg),
      targets: snapshotTargets,
      width: screenSize.$1,
      height: screenSize.$2,
      frontApp: 'Safari',
    );
  }

  @override
  Future<Offset> mouseLocation() async => const Offset(42, 42);

  (double, double, double, double)? lastRegion;

  @override
  Future<ScreenSnapshot> snapshotRegion(
    double x,
    double y,
    double width,
    double height,
  ) async {
    lastRegion = (x, y, width, height);
    return ScreenSnapshot(
      jpeg: Uint8List.fromList(_jpeg),
      targets: '',
      width: width,
      height: height,
      frontApp: 'Safari',
    );
  }

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
