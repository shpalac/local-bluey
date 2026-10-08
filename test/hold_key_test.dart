import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/hold_key.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  late HoldKeyMachine m;
  setUp(() => m = HoldKeyMachine());

  test('held alone past the threshold starts, release sends (#228)', () {
    expect(m.keyDown(HoldKey.rightCommand, at(0)), HoldKeyAction.none);
    expect(m.tick(at(399)), HoldKeyAction.none);
    expect(m.tick(at(400)), HoldKeyAction.start);
    expect(m.state, HoldKeyState.recording);
    expect(m.keyUp(HoldKey.rightCommand, at(2000)), HoldKeyAction.send);
    expect(m.state, HoldKeyState.idle);
  });

  test('released before the threshold does nothing', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    expect(m.keyUp(HoldKey.rightCommand, at(200)), HoldKeyAction.none);
    expect(m.tick(at(1000)), HoldKeyAction.none);
    expect(m.state, HoldKeyState.idle);
  });

  test('another key during the hold disqualifies it (Cmd+C, Cmd+Tab)', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    expect(m.keyDown(HoldKey.other, at(100)), HoldKeyAction.none);
    expect(m.tick(at(1000)), HoldKeyAction.none);
    expect(m.keyUp(HoldKey.rightCommand, at(1200)), HoldKeyAction.none);
    expect(m.state, HoldKeyState.idle);
  });

  test('a key pressed before the trigger key never starts a hold', () {
    expect(m.keyDown(HoldKey.other, at(0)), HoldKeyAction.none);
    m.keyDown(HoldKey.rightCommand, at(50));
    expect(m.tick(at(2000)), HoldKeyAction.start);
  });

  test('another key while recording cancels the recording', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    m.tick(at(500));
    expect(m.keyDown(HoldKey.other, at(800)), HoldKeyAction.cancel);
    expect(m.keyUp(HoldKey.rightCommand, at(900)), HoldKeyAction.none);
  });

  test('Esc cancels a running recording and blocks until release', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    m.tick(at(500));
    expect(m.escape(at(900)), HoldKeyAction.cancel);
    expect(m.tick(at(5000)), HoldKeyAction.none);
    expect(m.keyUp(HoldKey.rightCommand, at(6000)), HoldKeyAction.none);
  });

  test('Esc before the threshold blocks the hold', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    expect(m.escape(at(100)), HoldKeyAction.none);
    expect(m.tick(at(2000)), HoldKeyAction.none);
  });

  test('Esc with no hold in progress is ignored', () {
    expect(m.escape(at(0)), HoldKeyAction.none);
    expect(m.state, HoldKeyState.idle);
  });

  test('auto-repeat of the trigger key does not restart the timer', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    m.keyDown(HoldKey.rightCommand, at(300));
    expect(m.tick(at(400)), HoldKeyAction.start);
    m.keyDown(HoldKey.rightCommand, at(450));
    expect(m.state, HoldKeyState.recording);
  });

  test('a stuck key is sent at the recording cap and then blocked', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    m.tick(at(400));
    expect(m.tick(at(400 + 119999)), HoldKeyAction.none);
    expect(m.tick(at(400 + 120000)), HoldKeyAction.send);
    expect(m.tick(at(400 + 130000)), HoldKeyAction.none);
    expect(m.keyUp(HoldKey.rightCommand, at(400 + 140000)), HoldKeyAction.none);
  });

  test('reset cancels a recording, never sends (sleep, lock, deactivate)', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    m.tick(at(500));
    expect(m.reset(), HoldKeyAction.cancel);
    expect(m.state, HoldKeyState.idle);
    expect(m.keyUp(HoldKey.rightCommand, at(900)), HoldKeyAction.none);
  });

  test('reset before recording is silent', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    expect(m.reset(), HoldKeyAction.none);
    expect(m.tick(at(2000)), HoldKeyAction.none);
  });

  test('a different configured key and threshold are honoured', () {
    final fn = HoldKeyMachine(
      key: HoldKey.fn,
      threshold: const Duration(milliseconds: 150),
    );
    fn.keyDown(HoldKey.rightCommand, at(0));
    expect(fn.state, HoldKeyState.idle);
    fn.keyUp(HoldKey.rightCommand, at(10));
    fn.keyDown(HoldKey.fn, at(20));
    expect(fn.tick(at(169)), HoldKeyAction.none);
    expect(fn.tick(at(170)), HoldKeyAction.start);
    expect(fn.keyUp(HoldKey.fn, at(900)), HoldKeyAction.send);
  });

  test('releasing a different key never ends the hold', () {
    m.keyDown(HoldKey.rightCommand, at(0));
    m.tick(at(500));
    expect(m.keyUp(HoldKey.other, at(600)), HoldKeyAction.none);
    expect(m.state, HoldKeyState.recording);
  });
}
