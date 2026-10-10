import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/safety_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Narrow read overrides enter the actual production authorize await boundaries.
class HeldReads extends SafetyGate {
  HeldReads({this.enabledRead, this.appsRead, super.onConfirm});
  Future<bool> Function()? enabledRead;
  Future<Set<String>> Function()? appsRead;
  @override
  Future<bool> isEnabled() => enabledRead?.call() ?? super.isEnabled();
  @override
  Future<Set<String>> allowlist() => appsRead?.call() ?? super.allowlist();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final resume in [false, true]) {
    for (final answer in ['yes', 'no', 'error']) {
      test(
        'entered confirmation kill ${resume ? "reset" : "held"} $answer denies old work',
        () async {
          final entered = Completer<void>(), response = Completer<bool>();
          var calls = 0;
          final gate = SafetyGate(
            onConfirm: (_) {
              calls++;
              if (calls == 1) {
                entered.complete();
                return response.future;
              }
              return Future.value(true);
            },
          );
          final pending = gate.authorize('open_app', {'name': 'Safari'});
          await entered.future;
          gate.kill();
          if (resume) gate.reset();
          if (answer == 'error') {
            response.completeError(StateError('old'));
          } else {
            response.complete(answer == 'yes');
          }
          expect(await pending, isFalse);
          expect(calls, 1);
          if (resume) {
            expect(
              await gate.authorize('open_app', {'name': 'Safari'}),
              isTrue,
            );
            expect(calls, 2);
          } else {
            expect(
              await gate.authorize('open_app', {'name': 'Safari'}),
              isFalse,
            );
          }
        },
      );
    }
  }
  for (final stage in ['enabled', 'allowlist']) {
    for (final resume in [false, true]) {
      for (final error in [false, true]) {
        test(
          'entered $stage kill ${resume ? "reset" : "held"} ${error ? "error" : "success"} no confirm',
          () async {
            final entered = Completer<void>(), response = Completer<dynamic>();
            var confirms = 0, first = true;
            final gate = HeldReads(
              onConfirm: (_) async {
                confirms++;
                return true;
              },
            );
            if (stage == 'enabled') {
              gate.enabledRead = () async {
                if (first) {
                  first = false;
                  entered.complete();
                  return await response.future as bool;
                }
                return true;
              };
            } else {
              gate.appsRead = () async {
                if (first) {
                  first = false;
                  entered.complete();
                  return await response.future as Set<String>;
                }
                return {};
              };
            }
            final pending = gate.authorize('open_app', {'name': 'Safari'});
            await entered.future;
            gate.kill();
            if (resume) gate.reset();
            if (error) {
              response.completeError(StateError('stale'));
            } else {
              response.complete(stage == 'enabled' ? false : <String>{});
            }
            expect(await pending, isFalse);
            expect(confirms, 0);
            if (resume) {
              expect(
                await gate.authorize('open_app', {'name': 'Safari'}),
                isTrue,
              );
              expect(confirms, 1);
            }
          },
        );
      }
    }
  }
  test('safe early success after enabled read still invalidated', () async {
    final response = Completer<bool>(), entered = Completer<void>();
    final gate = HeldReads(
      enabledRead: () {
        entered.complete();
        return response.future;
      },
    );
    final pending = gate.authorize('read_screen', {});
    await entered.future;
    gate.kill();
    gate.reset();
    response.complete(true);
    expect(await pending, isFalse);
  });
  for (final stage in ['enabled', 'allowlist', 'confirm']) {
    test('current $stage error remains visible', () async {
      final gate = HeldReads(
        onConfirm: (_) async {
          if (stage == 'confirm') throw StateError('current');
          return true;
        },
      );
      if (stage == 'enabled') {
        gate.enabledRead = () async => throw StateError('current');
      }
      if (stage == 'allowlist') {
        gate.appsRead = () async => throw StateError('current');
      }
      await expectLater(
        gate.authorize('open_app', {'name': 'Safari'}),
        throwsStateError,
      );
    });
  }
  test('kill snapshot isolates throwing callbacks and defers additions', () {
    final gate = SafetyGate();
    final seen = <String>[];
    gate.onKill(() {
      seen.add('first');
      throw StateError('private');
    });
    gate.onKill(() {
      seen.add('adding');
      gate.onKill(() => seen.add('new'));
    });
    gate.onKill(() => seen.add('last'));
    gate.kill();
    expect(seen, ['first', 'adding', 'last']);
    expect(gate.killed, isTrue);
    expect(gate.generation, 1);
    expect(gate.killListenerFailures, 1);
    seen.clear();
    gate.kill();
    expect(seen, ['first', 'adding', 'last', 'new']);
    expect(gate.generation, 2);
    expect(gate.killListenerFailures, 2);
  });
  test('reentrant kill invalidates but does not recursively dispatch', () {
    final gate = SafetyGate();
    var recursive = 0, last = 0;
    gate.onKill(() {
      recursive++;
      gate.kill();
    });
    gate.onKill(() => last++);
    gate.kill();
    expect(recursive, 1);
    expect(last, 1);
    expect(gate.generation, 2);
    expect(gate.killed, isTrue);
    gate.kill();
    expect(recursive, 2);
    expect(last, 2);
    expect(gate.generation, 4);
  });
  test(
    'kill inside front app lookup cannot open a fresh confirmation',
    () async {
      var calls = 0;
      final gate = SafetyGate(
        onConfirm: (_) async {
          calls++;
          return true;
        },
      );
      gate.frontAppProvider = () {
        gate.kill();
        gate.reset();
        return 'Safari';
      };
      expect(await gate.authorize('click', {}), isFalse);
      expect(calls, 0);
    },
  );
}
