import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('redacts emails, card numbers and id-shaped numbers', () {
    final out = PrivacyGuard.redact(
      'mail me at a.b@corp.com, card 4111 1111 1111 1111, id 123456789',
    );
    expect(out, isNot(contains('a.b@corp.com')));
    expect(out, isNot(contains('4111')));
    expect(out, isNot(contains('123456789')));
    expect(out, contains('[redacted]'));
  });

  test('local-only refuses remote providers, allows localhost', () async {
    SharedPreferences.setMockInitialValues({'privacy.localOnly': true});
    const remote = BrainSettings(
      backend: BrainBackend.openAiCompatible,
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'm',
    );
    expect(await PrivacyGuard.refusal(remote), isNotNull);
    const local = BrainSettings(
      backend: BrainBackend.ollama,
      baseUrl: 'http://localhost:11434',
      model: 'm',
    );
    expect(await PrivacyGuard.refusal(local), isNull);
  });

  test('local-only off never refuses', () async {
    const remote = BrainSettings(
      backend: BrainBackend.openAiCompatible,
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'm',
    );
    expect(await PrivacyGuard.refusal(remote), isNull);
  });
}
