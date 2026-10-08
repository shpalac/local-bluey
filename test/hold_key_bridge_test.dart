import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/hold_key.dart';
import 'package:local_bluey/services/hold_key_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('local_bluey/holdkey');
  late StreamController<dynamic> events;
  late List<String> calls;
  late bool granted;
  late DateTime clock;
  late List<HoldKeyAction> actions;
  late HoldKeyBridge bridge;

  setUp(() {
    events = StreamController<dynamic>.broadcast();
    calls = [];
    granted = true;
    clock = DateTime(2026, 1, 1, 12);
    actions = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'permission':
            case 'requestPermission':
              return granted;
            case 'start':
              return granted;
          }
          return null;
        });
    bridge = HoldKeyBridge(
      machine: HoldKeyMachine(),
      onAction: actions.add,
      events: events.stream,
      now: () => clock,
      tickEvery: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await bridge.disable();
    await events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> send(String type, String key) async {
    events.add({'type': type, 'key': key});
    await Future<void>.delayed(Duration.zero);
  }

  test('hold, threshold tick and release start then send (#228)', () async {
    expect(await bridge.enable(), isTrue);
    await send('down', 'rightCommand');
    clock = clock.add(const Duration(milliseconds: 450));
    bridge.tick();
    await send('up', 'rightCommand');
    expect(actions, [HoldKeyAction.start, HoldKeyAction.send]);
  });

  test('another key or Esc cancels a running recording', () async {
    await bridge.enable();
    await send('down', 'rightCommand');
    clock = clock.add(const Duration(milliseconds: 450));
    bridge.tick();
    await send('down', 'other');
    expect(actions, [HoldKeyAction.start, HoldKeyAction.cancel]);
    actions.clear();
    await send('up', 'rightCommand');
    await send('down', 'rightCommand');
    clock = clock.add(const Duration(milliseconds: 450));
    bridge.tick();
    await send('escape', 'other');
    expect(actions, [HoldKeyAction.start, HoldKeyAction.cancel]);
  });

  test('a short hold or a combo never starts', () async {
    await bridge.enable();
    await send('down', 'rightCommand');
    await send('down', 'other');
    clock = clock.add(const Duration(seconds: 2));
    bridge.tick();
    await send('up', 'rightCommand');
    expect(actions, isEmpty);
  });

  test('missing permission leaves the shortcut off (#228)', () async {
    granted = false;
    expect(await bridge.hasPermission(), isFalse);
    expect(await bridge.enable(), isFalse);
    expect(bridge.enabled, isFalse);
    await send('down', 'rightCommand');
    clock = clock.add(const Duration(seconds: 2));
    bridge.tick();
    expect(actions, isEmpty);
  });

  test('a missing native side is a quiet no, not a crash', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await bridge.enable(), isFalse);
  });

  test('disable cancels a running recording and stops the listener', () async {
    await bridge.enable();
    await send('down', 'rightCommand');
    clock = clock.add(const Duration(milliseconds: 450));
    bridge.tick();
    await bridge.disable();
    expect(actions, [HoldKeyAction.start, HoldKeyAction.cancel]);
    expect(bridge.enabled, isFalse);
    expect(calls, contains('stop'));
  });

  test('reset (sleep, lock, deactivate) cancels the hold', () async {
    await bridge.enable();
    await send('down', 'rightCommand');
    clock = clock.add(const Duration(milliseconds: 450));
    bridge.tick();
    bridge.reset();
    expect(actions.last, HoldKeyAction.cancel);
  });

  test('malformed events are ignored', () async {
    await bridge.enable();
    events.add('nonsense');
    events.add({'type': 'down', 'key': 'unknown'});
    await Future<void>.delayed(Duration.zero);
    expect(actions, isEmpty);
  });
}
