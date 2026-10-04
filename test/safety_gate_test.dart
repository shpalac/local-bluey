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
}
