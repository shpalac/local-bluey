import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/sensitive_content_gate.dart';

void main() {
  test('benign English and Hebrew project windows allow', () {
    for (final title in ['Example project', 'מסמך לדוגמה', 'README — GitHub']) {
      expect(
        SensitiveContentGate.beforeCapture(app: 'Editor', title: title),
        SensitiveVerdict.allow,
      );
    }
  });

  test('unknown app/title and outsize metadata fail closed', () {
    for (final entry in [
      (app: '', title: 'Project'),
      (app: 'Editor', title: ''),
      (app: 'Editor', title: null),
      (app: 'Editor', title: 'x' * 513),
    ]) {
      expect(
        SensitiveContentGate.beforeCapture(app: entry.app, title: entry.title),
        SensitiveVerdict.unknown,
      );
    }
  });

  test('locked and private browsing denied regardless of consent', () {
    expect(
      SensitiveContentGate.beforeCapture(
        app: 'Editor', title: 'Project', locked: true,
      ),
      SensitiveVerdict.locked,
    );
    for (final title in ['New Incognito Tab', 'Private Browsing', 'חלון פרטי']) {
      expect(
        SensitiveContentGate.beforeCapture(app: 'Browser', title: title),
        SensitiveVerdict.privateWindow,
      );
    }
  });

  test('password, authentication, finance and Hebrew windows blocked', () {
    for (final title in [
      'Password manager', 'Sign in', '2FA code',
      'חשבון בנק', 'התחברות', 'כרטיס אשראי',
    ]) {
      expect(
        SensitiveContentGate.beforeCapture(app: 'Browser', title: title),
        SensitiveVerdict.sensitiveWindow,
        reason: title,
      );
    }
  });

  test('recognised English/Hebrew PII and secrets blocked before egress', () {
    for (final text in [
      'Email: demo@example.com',
      'Password: excellenthorses',
      'API_KEY=example',
      'Bearer abc',
      'Card 4111 1111 1111 1111',
      'מספר זהות 123456789',
      'כרטיס אשראי',
      'קוד אימות 123456',
      'ghp_abcdefghijklmnopqrstuvwxyz',
    ]) {
      expect(
        SensitiveContentGate.beforeEgress(
          text: text, exactFrameVerified: true,
        ),
        SensitiveVerdict.sensitiveText,
        reason: 'PII fixture should block',
      );
    }
  });

  test('verified benign/blank OCR may pass; missing OCR must fail', () {
    expect(
      SensitiveContentGate.beforeEgress(
        text: 'README — Tasks', exactFrameVerified: true,
      ),
      SensitiveVerdict.allow,
    );
    expect(
      SensitiveContentGate.beforeEgress(
        text: '', exactFrameVerified: true,
      ),
      SensitiveVerdict.allow,
    );
    for (final verified in [false, true]) {
      expect(
        SensitiveContentGate.beforeEgress(
          text: null, exactFrameVerified: verified,
        ),
        SensitiveVerdict.unverifiedText,
      );
    }
    expect(
      SensitiveContentGate.beforeEgress(
        text: 'Tasks', exactFrameVerified: false,
      ),
      SensitiveVerdict.unverifiedText,
    );
    expect(
      SensitiveContentGate.beforeEgress(
        text: 'a' * 65537, exactFrameVerified: true,
      ),
      SensitiveVerdict.unverifiedText,
    );
  });

  test('refusal reports reason only, not the secret text', () {
    final verdict = SensitiveContentGate.beforeEgress(
      text: 'password: secret123', exactFrameVerified: true,
    );
    expect(verdict.name, 'sensitiveText');
    expect(verdict.toString(), isNot(contains('secret123')));
  });
}
