import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// One process-wide write queue and delete-all epoch. Every watchdog
  /// instance (live owner, a retired one finishing its work, a test double)
  /// shares them, so an explicit delete-all is ordered after every entered
  /// baseline write and invalidates every entered observation, whichever
  /// instance started it.
  static Future<void> _writes = Future<void>.value();
  static int _epoch = 0;
  static const _epochKey = '#epoch';

  Map<String, int> _observations() => {
    for (final p in onboardingPermissions) p.id: _dismissals[p.id] ?? 0,
    _epochKey: _epoch,
  };
  bool _current(String id, Map<String, int> observed) =>
      observed[id] == (_dismissals[id] ?? 0) && observed[_epochKey] == _epoch;

  static int _pending = 0;

  static Future<T> _ordered<T>(Future<T> Function() action) {
    // An idle queue starts fresh so a future from an abandoned zone can never
    // stall later work.
    final prior = _pending == 0 ? Future<void>.value() : _writes;
    _pending++;
    final next = prior.then((_) => action());
    _writes = next
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _pending--);
    return next;
  }

  /// Test seam: store used by [clearAllBaselines] instead of the platform one.
  @visibleForTesting
  static SharedPreferences? debugClearStore;

  /// Data-registry delete-all. Invalidates every entered observation
  /// synchronously, then removes all baseline keys after entered writes.
  /// Observations begun afterwards may record a fresh baseline. A refused or
  /// thrown removal is reported as a generic failure and a fresh call retries.
  static Future<void> clearAllBaselines() {
    _epoch++;
    return _ordered(() async {
      final store = debugClearStore ?? await SharedPreferences.getInstance();
      var failed = false;
      for (final key in store.getKeys().toList()) {
        if (!key.startsWith(_kPrefix)) continue;
        try {
          if (!await store.remove(key)) failed = true;
        } catch (_) {
          failed = true;
        }
      }
      if (failed) throw StateError('Permission baseline was not cleared.');
    });
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
