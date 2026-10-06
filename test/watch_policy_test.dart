import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/watch_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('hard deny list always wins, even over an allowlist entry', () async {
    await WatchPolicy.addToAllowlist('1Password');
    expect(
      await WatchPolicy.verdict(frontApp: '1Password'),
      WatchVerdict.hardDenied,
    );
    expect(
      await WatchPolicy.verdict(frontApp: 'System Settings'),
      WatchVerdict.hardDenied,
    );
    expect(
      await WatchPolicy.verdict(frontApp: 'Keychain Access'),
      WatchVerdict.hardDenied,
    );
  });

  test('banking surfaces denied by app name and by window title', () async {
    expect(
      await WatchPolicy.verdict(frontApp: 'Bank Hapoalim'),
      WatchVerdict.hardDenied,
    );
    expect(
      await WatchPolicy.verdict(
        frontApp: 'Safari',
        windowTitle: 'Bank Leumi - Login',
      ),
      WatchVerdict.hardDenied,
    );
  });

  test('private browser windows denied in every browser language', () async {
    for (final title in [
      'New Incognito Tab',
      'Private Browsing',
      'Private Window',
      'InPrivate browsing',
      'גלישה פרטית',
      'חלון פרטי',
    ]) {
      expect(
        await WatchPolicy.verdict(frontApp: 'Safari', windowTitle: title),
        WatchVerdict.privateWindow,
        reason: title,
      );
    }
  });

  test('lock screen denies before anything else', () async {
    await WatchPolicy.addToAllowlist('Safari');
    expect(
      await WatchPolicy.verdict(frontApp: 'Safari', locked: true),
      WatchVerdict.locked,
    );
  });

  test('allowlist matches normalized names only', () async {
    await WatchPolicy.addToAllowlist('Safari.app');
    expect(await WatchPolicy.verdict(frontApp: 'safari'), WatchVerdict.allow);
    expect(
      await WatchPolicy.verdict(frontApp: 'Xcode'),
      WatchVerdict.notAllowlisted,
    );
  });

  test('user denylist denies on top of the allowlist', () async {
    await WatchPolicy.addToAllowlist('Notes');
    await WatchPolicy.addToUserDenylist('notes');
    expect(
      await WatchPolicy.verdict(frontApp: 'Notes'),
      WatchVerdict.hardDenied,
    );
  });

  test('allowlist edits persist and normalize', () async {
    await WatchPolicy.addToAllowlist(' Safari.app ');
    await WatchPolicy.addToAllowlist('safari');
    expect(await WatchPolicy.allowlist(), ['safari']);
    await WatchPolicy.removeFromAllowlist('SAFARI');
    expect(await WatchPolicy.allowlist(), isEmpty);
  });
}
