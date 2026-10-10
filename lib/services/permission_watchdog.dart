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

  final _dismissals = <String, int>{};
  Future<void> _writes = Future<void>.value();
  Map<String, int> _observations() => {
    for (final p in onboardingPermissions) p.id: _dismissals[p.id] ?? 0,
  };
  bool _current(String id, Map<String, int> observed) =>
      observed[id] == (_dismissals[id] ?? 0);

  Future<T> _ordered<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

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
    final observed = _observations();
    final now = await _checkAll();
    await _ordered(() async {
      final store = await _store;
      for (final granted in now.entries) {
        if (_current(granted.key, observed) && granted.value) {
          await store.setBool('$_kPrefix${granted.key}', true);
        }
      }
    });
    return now;
  }

  /// Re-checks every permission. Newly granted ones join the baseline;
  /// permissions that were granted before and are now missing come back as
  /// revoked.
  Future<List<OnboardingPermission>> recheckRevoked() async {
    final observed = _observations();
    final now = await _checkAll();
    final revoked = await _ordered(() async {
      final store = await _store;
      final result = <OnboardingPermission>[];
      for (final p in onboardingPermissions) {
        if (!_current(p.id, observed)) continue;
        final was = store.getBool('$_kPrefix${p.id}') ?? false;
        final isNow = now[p.id] ?? false;
        if (isNow && !was) {
          await store.setBool('$_kPrefix${p.id}', true);
        } else if (was && !isNow) {
          result.add(p);
        }
      }
      return result;
    });
    return revoked.where((p) => _current(p.id, observed)).toList();
  }

  /// Forgets the baseline for one permission (the user dismissed the card):
  /// it must be granted again before it can be reported revoked once more.
  /// Invalidates entered probes synchronously and orders removal after entered
  /// writes. New post-clear observations may establish a fresh grant baseline.
  Future<void> clearBaseline(String id) {
    _dismissals[id] = (_dismissals[id] ?? 0) + 1;
    return _ordered(() async {
      await (await _store).remove('$_kPrefix$id');
    });
  }
}
