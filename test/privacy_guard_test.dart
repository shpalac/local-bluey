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

  test('isLocalUrl accepts loopback forms only (#121)', () {
    expect(PrivacyGuard.isLocalUrl('http://localhost:11434'), isTrue);
    expect(PrivacyGuard.isLocalUrl('http://127.0.0.1:11434/v1'), isTrue);
    expect(PrivacyGuard.isLocalUrl('http://127.0.0.2'), isTrue);
    expect(PrivacyGuard.isLocalUrl('http://0.0.0.0:8080'), isTrue);
    expect(PrivacyGuard.isLocalUrl('http://[::1]:11434'), isTrue);
    expect(PrivacyGuard.isLocalUrl('http://[::ffff:127.0.0.1]'), isTrue);
  });

  test('isLocalUrl rejects mDNS and remote hosts (#121)', () {
    expect(PrivacyGuard.isLocalUrl('http://nas.local:11434'), isFalse);
    expect(PrivacyGuard.isLocalUrl('http://example.com'), isFalse);
    expect(PrivacyGuard.isLocalUrl('not a url'), isFalse);
    expect(PrivacyGuard.isLocalUrl('ftp://127.0.0.1'), isFalse);
  });

  test('refusalForUrl gates any endpoint in local-only mode (#120)', () async {
    SharedPreferences.setMockInitialValues({'privacy.localOnly': true});
    expect(
      await PrivacyGuard.refusalForUrl('http://api.openai.com/v1'),
      isNotNull,
    );
    expect(await PrivacyGuard.refusalForUrl('http://127.0.0.1:11434'), isNull);
  });
}
