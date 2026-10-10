import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/watch_policy.dart';

void main() {
  for (final name in [
    '1Password 7', 'Bitwarden Desktop', 'KeePassXC 2.7', 'Passwords',
    'Proton Pass', 'ProtonPass.app', 'NordPass', 'Strongbox', 'Authy Desktop',
    'Google Authenticator', 'Microsoft Authenticator', 'Wallet', 'Keeper',
    'RoboForm', ' Keychain Access.app ', 'System Settings',
    // Synthetic bundle-style identifiers exercise branded-token matching;
    // they do not assert all real vendor bundle IDs use these spellings.
    'com.vendor.1password.desktop', 'com.vendor.bitwarden',
  ]) {
    test('known app/identity denied despite allowlist: $name', () async {
      expect(
        await WatchPolicy.verdict(
          frontApp: name,
          allowedApps: [name],
          deniedApps: [],
        ),
        WatchVerdict.hardDenied,
      );
    });
  }
  for (final title in [
    'Bitwarden Web Vault', '1Password - Vault', 'My KeePassXC Database',
    'Proton Pass - Vault', 'NordPass - Password Manager', 'Passwords',
    'Wallet', 'Keeper Vault', 'Strongbox 1.2', 'Keychain Access',
    // Intentional false positives: articles with distinctive brand mentions
    // and pages named exactly a generic secret app are denied conservatively.
    'Review of Bitwarden Desktop', 'Passwords',
  ]) {
    test('known title denied in allowlisted browser: $title', () async {
      expect(
        await WatchPolicy.verdict(
          frontApp: 'Safari',
          windowTitle: title,
          allowedApps: ['safari'],
          deniedApps: [],
        ),
        WatchVerdict.hardDenied,
      );
    });
  }
  for (final name in [
    'Pass Notes',
    'Key Sketch',
    'Vault Planner',
    'Goalkeeper',
    'Strongboxer',
    'Passwordsmith',
    'NotBitwarden',
    '1Passwordish',
  ]) {
    test('unrelated app is not denied by generic substring: $name', () async {
      expect(
        await WatchPolicy.verdict(
          frontApp: name,
          windowTitle: 'Project notes',
          allowedApps: [name],
          deniedApps: [],
        ),
        WatchVerdict.allow,
      );
    });
  }
  for (final title in [
    'Passing tests',
    'Keyboard shortcuts',
    'Vault architecture notes',
    'My wallet design',
    'Goalkeeper training',
    'Passwords in fiction',
    'Strongbox construction',
    'Bitwardens overview',
  ]) {
    test('unrelated normal title stays allowed: $title', () async {
      expect(
        await WatchPolicy.verdict(
          frontApp: 'Safari',
          windowTitle: title,
          allowedApps: ['safari'],
          deniedApps: [],
        ),
        WatchVerdict.allow,
      );
    });
  }
  test('lock/private precedence retained over secret aliases', () async {
    expect(
      await WatchPolicy.verdict(frontApp: '1Password', locked: true),
      WatchVerdict.locked,
    );
    expect(
      await WatchPolicy.verdict(
        frontApp: 'Safari',
        windowTitle: 'Bitwarden - Private Window',
      ),
      WatchVerdict.privateWindow,
    );
  });
}
