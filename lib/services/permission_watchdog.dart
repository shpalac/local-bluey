import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_checks.dart';

/// Remembers which permissions have ever been granted and reports the ones
/// later found revoked (#174): an app-resume re-check turns "the grant is
/// gone" into a one-tap fix-it card instead of a broken tool call.
class PermissionWatchdog {
  PermissionWatchdog({required this.checker, this.prefsOverride});

  /// Supplies the current grant state per permission.
  final PermissionChecker checker;

  /// Test seam: an injected store wins over the platform default.
  final SharedPreferences? prefsOverride;
  SharedPreferences? _prefs;

  static const _kPrefix = 'watchdog.granted.';

  /// The grant-history store (test seam: [prefsOverride] wins).
  Future<SharedPreferences> get _store async =>
      _prefs ??= prefsOverride ?? await SharedPreferences.getInstance();

  Future<bool> _statusOf(String id) => switch (id) {
    'accessibility' => checker.accessibility(),
    'screen_recording' => checker.screenRecording(),
    'microphone' => checker.microphone(),
    _ => checker.localNetwork(),
  };

  Future<Map<String, bool>> _checkAll() async => {
    for (final p in onboardingPermissions) p.id: await _statusOf(p.id),
  };

  /// Snapshots current grants as the baseline (e.g. when onboarding
  /// finishes). Returns the live map.
  Future<Map<String, bool>> recordGranted() async {
    final now = await _checkAll();
    final store = await _store;
    for (final granted in now.entries) {
      if (granted.value) {
        await store.setBool('$_kPrefix${granted.key}', true);
      }
    }
    return now;
  }

  /// Re-checks every permission. Newly granted ones join the baseline;
  /// permissions that were granted before and are now missing come back as
  /// revoked.
  Future<List<OnboardingPermission>> recheckRevoked() async {
    final now = await _checkAll();
    final store = await _store;
    final revoked = <OnboardingPermission>[];
    for (final p in onboardingPermissions) {
      final was = store.getBool('$_kPrefix${p.id}') ?? false;
      final isNow = now[p.id] ?? false;
      if (isNow && !was) {
        await store.setBool('$_kPrefix${p.id}', true);
      } else if (was && !isNow) {
        revoked.add(p);
      }
    }
    return revoked;
  }

  /// Forgets the baseline for one permission (the user dismissed the card):
  /// it must be granted again before it can be reported revoked once more.
  Future<void> clearBaseline(String id) async =>
      (await _store).remove('$_kPrefix$id');
}
