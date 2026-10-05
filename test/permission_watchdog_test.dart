import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/permission_watchdog.dart';

class _StubChecker extends PermissionChecker {
  _StubChecker(this.grants);
  final Map<String, bool> grants;
  @override
  Future<bool> accessibility() async => grants['accessibility'] ?? false;
  @override
  Future<bool> screenRecording() async => grants['screen_recording'] ?? false;
  @override
  Future<bool> microphone() async => grants['microphone'] ?? false;
  @override
  Future<bool> localNetwork() async => grants['local_network'] ?? false;
}

PermissionWatchdog _wd(Map<String, bool> grants, SharedPreferences prefs) =>
    PermissionWatchdog(checker: _StubChecker(grants), prefsOverride: prefs);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recordGranted stores only granted permissions', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final wd = _wd({'accessibility': true}, prefs);
    await wd.recordGranted();
    expect(prefs.getBool('watchdog.granted.accessibility'), isTrue);
    expect(prefs.getBool('watchdog.granted.microphone'), isNull);
  });

  test('recheckRevoked reports a grant that was lost', () async {
    SharedPreferences.setMockInitialValues({
      'watchdog.granted.accessibility': true,
      'watchdog.granted.microphone': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final wd = _wd({'microphone': true}, prefs);
    final revoked = await wd.recheckRevoked();
    expect(revoked.map((p) => p.id), ['accessibility']);
  });

  test(
    'recheckRevoked adds newly granted permissions to the baseline',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final wd = _wd({'microphone': true}, prefs);
      final revoked = await wd.recheckRevoked();
      expect(revoked, isEmpty);
      expect(prefs.getBool('watchdog.granted.microphone'), isTrue);
    },
  );

  test('clearBaseline stops reporting the dismissed permission', () async {
    SharedPreferences.setMockInitialValues({
      'watchdog.granted.accessibility': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final wd = _wd({}, prefs);
    expect(await wd.recheckRevoked(), isNotEmpty);
    await wd.clearBaseline('accessibility');
    expect(await wd.recheckRevoked(), isEmpty);
  });

  test('permission kept granted is never revoked', () async {
    SharedPreferences.setMockInitialValues({
      'watchdog.granted.microphone': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final wd = _wd({'microphone': true}, prefs);
    expect(await wd.recheckRevoked(), isEmpty);
  });
}
