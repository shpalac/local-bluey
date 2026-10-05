import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/safety_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('safe tools always pass; risky tools ask the human', () async {
    var asked = 0;
    final gate = SafetyGate(
      onConfirm: (_) async {
        asked++;
        return true;
      },
    );
    expect(await gate.authorize('look_at_screen', {}), isTrue);
    expect(asked, 0);
    expect(await gate.authorize('click', {'target_id': 'C1'}), isTrue);
    expect(asked, 1);
  });

  test('deny by default when no confirm hook is wired', () async {
    final gate = SafetyGate();
    expect(await gate.authorize('type_text', {'text': 'hi'}), isFalse);
  });

  test('kill switch blocks everything until reset', () async {
    final gate = SafetyGate(onConfirm: (_) async => true);
    gate.kill();
    expect(await gate.authorize('look_at_screen', {}), isFalse);
    gate.reset();
    expect(await gate.authorize('look_at_screen', {}), isTrue);
  });

  test('allowlist rejects non-listed apps without asking', () async {
    SharedPreferences.setMockInitialValues({'safety.appAllowlist': 'safari'});
    var asked = 0;
    final gate = SafetyGate(
      onConfirm: (_) async {
        asked++;
        return true;
      },
    );
    expect(await gate.authorize('open_app', {'name': 'Terminal'}), isFalse);
    expect(asked, 0);
    expect(await gate.authorize('open_app', {'name': 'Safari'}), isTrue);
    expect(asked, 1);
  });

  test('disabled gate lets everything through', () async {
    SharedPreferences.setMockInitialValues({'safety.enabled': false});
    final gate = SafetyGate();
    expect(await gate.authorize('click', {}), isTrue);
  });

  test('kill during the confirmation dialog still denies (#107)', () async {
    late final SafetyGate gate;
    gate = SafetyGate(
      onConfirm: (_) async {
        gate.kill();
        return true; // user taps Allow after the kill
      },
    );
    expect(await gate.authorize('click', {'target_id': 'C1'}), isFalse);
  });

  test('kill bumps the generation so a resumed run stays stopped (#107)', () {
    final gate = SafetyGate();
    final gen = gate.generation;
    gate.kill();
    gate.reset();
    expect(gate.generation, isNot(gen));
  });

  test('type_text description shows the full text and the Return (#108)', () {
    final short = SafetyGate.describe('type_text', {'text': 'hello'});
    expect(short, 'Type "hello"');
    final withReturn = SafetyGate.describe('type_text', {
      'text': 'send it',
      'press_return': true,
    });
    expect(withReturn, contains('press Return'));
    final long = '${'a' * 150}TAIL-MARKER${'b' * 88}';
    final desc = SafetyGate.describe('type_text', {'text': long});
    expect(desc, contains('TAIL-MARKER'));
    expect(desc, contains('249 characters total'));
  });

  test(
    'press_keys description is null-safe; click shows coordinates (#108)',
    () {
      expect(SafetyGate.describe('press_keys', {}), contains('no keys'));
      expect(
        SafetyGate.describe('click', {'x': 500, 'y': 300}),
        contains('(500, 300)'),
      );
    },
  );

  test(
    'default-deny apps are refused even with an empty allowlist (#109)',
    () async {
      var asked = 0;
      final gate = SafetyGate(
        onConfirm: (_) async {
          asked++;
          return true;
        },
      );
      expect(await gate.authorize('open_app', {'name': 'Terminal'}), isFalse);
      expect(asked, 0);
      expect(await gate.authorize('open_app', {'name': 'Safari'}), isTrue);
    },
  );

  test(
    'default-deny app is allowed when explicitly allowlisted (#109)',
    () async {
      SharedPreferences.setMockInitialValues({
        'safety.appAllowlist': 'terminal, safari',
      });
      final gate = SafetyGate(onConfirm: (_) async => true);
      expect(await gate.authorize('open_app', {'name': 'Terminal'}), isTrue);
    },
  );

  test('input tools are checked against the front app (#109)', () async {
    final gate = SafetyGate(onConfirm: (_) async => true);
    gate.frontAppProvider = () => 'Terminal';
    expect(await gate.authorize('type_text', {'text': 'rm -rf ~'}), isFalse);
    gate.frontAppProvider = () => 'TextEdit';
    expect(await gate.authorize('type_text', {'text': 'hi'}), isTrue);
  });
}
