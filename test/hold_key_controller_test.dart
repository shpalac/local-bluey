import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/hold_key.dart';
import 'package:local_bluey/services/hold_key_bridge.dart';
import 'package:local_bluey/services/hold_key_controller.dart';
import 'package:local_bluey/ui/hold_key_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBridge extends HoldKeyBridge {
  _FakeBridge(HoldKeyMachine machine, void Function(HoldKeyAction) onAction)
    : super(machine: machine, onAction: onAction);

  static bool granted = true;
  static final created = <_FakeBridge>[];
  bool on = false;
  int requests = 0;
  bool reset_ = false;

  @override
  bool get enabled => on;
  @override
  Future<bool> hasPermission() async => granted;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<bool> enable() async => on = granted;
  @override
  Future<void> disable() async => on = false;
  @override
  void reset() => reset_ = true;
  void emit(HoldKeyAction a) => onAction(a);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = HoldKeySettings.instance;
  late List<String> log;
  late HoldKeyController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await settings.setEnabled(false);
    _FakeBridge.granted = true;
    _FakeBridge.created.clear();
    log = [];
    controller = HoldKeyController(
      settings: settings,
      onStart: () async => log.add('start'),
      onSend: () async => log.add('send'),
      onCancel: () async => log.add('cancel'),
      createBridge: (m, a) {
        final b = _FakeBridge(m, a);
        _FakeBridge.created.add(b);
        return b;
      },
    );
  });

  test('defaults: off, Right Command, 400 ms (#228)', () async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    expect(settings.enabled, isFalse);
    expect(settings.key, HoldKey.rightCommand);
    expect(settings.thresholdMs, 400);
  });

  test('choices persist and reload; junk values fall back', () async {
    await settings.setEnabled(true);
    await settings.setKey(HoldKey.fn);
    await settings.setThresholdMs(600);
    await settings.setKey(HoldKey.other);
    await settings.setThresholdMs(1);
    await settings.load();
    expect(settings.enabled, isTrue);
    expect(settings.key, HoldKey.fn);
    expect(settings.thresholdMs, 600);
    SharedPreferences.setMockInitialValues({
      'holdkey.key': 'bogus',
      'holdkey.thresholdMs': 7,
    });
    await settings.load();
    expect(settings.key, HoldKey.rightCommand);
    expect(settings.thresholdMs, 400);
  });

  test('nothing listens while the setting is off', () async {
    await controller.sync();
    expect(_FakeBridge.created, isEmpty);
    expect(controller.running, isFalse);
  });

  test(
    'switching on starts the listener; actions reach the recorder',
    () async {
      await settings.setEnabled(true);
      await controller.sync();
      expect(controller.running, isTrue);
      final b = _FakeBridge.created.single;
      b.emit(HoldKeyAction.start);
      b.emit(HoldKeyAction.send);
      b.emit(HoldKeyAction.cancel);
      expect(log, ['start', 'send', 'cancel']);
      await settings.setEnabled(false);
      await controller.sync();
      expect(controller.running, isFalse);
    },
  );

  test('missing permission: stays off and says so, no crash', () async {
    _FakeBridge.granted = false;
    await settings.setEnabled(true);
    await controller.sync();
    expect(controller.running, isFalse);
    expect(settings.permissionMissing, isTrue);
    expect(_FakeBridge.created.single.requests, 1);
    _FakeBridge.granted = true;
    await controller.sync();
    expect(controller.running, isTrue);
    expect(settings.permissionMissing, isFalse);
  });

  test(
    'changing the key restarts with the new machine; reset forwards',
    () async {
      await settings.setEnabled(true);
      await controller.sync();
      await settings.setKey(HoldKey.leftCommand);
      await controller.sync();
      expect(_FakeBridge.created, hasLength(2));
      expect(_FakeBridge.created.first.on, isFalse);
      expect(_FakeBridge.created.last.machine.key, HoldKey.leftCommand);
      controller.reset();
      expect(_FakeBridge.created.last.reset_, isTrue);
      await controller.dispose();
      expect(controller.running, isFalse);
    },
  );

  test('unsupported platforms never listen', () async {
    final c = HoldKeyController(
      settings: settings,
      supported: false,
      onStart: () async {},
      onSend: () async {},
      onCancel: () async {},
      createBridge: (m, a) => throw StateError('must not create'),
    );
    await settings.setEnabled(true);
    await c.sync();
    expect(c.running, isFalse);
  });

  testWidgets('settings section: off by default, options appear when on', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HoldKeySection())),
    );
    expect(find.text('Hold a key to talk'), findsOneWidget);
    expect(find.text('Key'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(settings.enabled, isTrue);
    expect(find.text('Key'), findsOneWidget);
    expect(find.text('Hold for'), findsOneWidget);
    settings.markPermissionMissing(true);
    await tester.pump();
    expect(find.textContaining('Input Monitoring'), findsWidgets);
    expect(find.textContaining('has not allowed'), findsOneWidget);
  });
}
