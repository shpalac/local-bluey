import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'privacy_guard.dart';
import 'watch_policy.dart';

/// Consent + session gate for proactive screen watching (#212).
///
/// Nothing in the observation path (capture, OCR, vision model, suggestions)
/// may run without going through [mayObserve]/[runIfAllowed] first. Sessions
/// are opt-in per session, short, and never persist: a fresh app launch is
/// always off, by construction - there is no "enabled" flag in storage.
class ScreenWatch extends ChangeNotifier {
  ScreenWatch._();

  /// The live session controller. Tests substitute [forTesting].
  static ScreenWatch instance = ScreenWatch._();

  /// An isolated instance for tests (injectable clock).
  @visibleForTesting
  factory ScreenWatch.forTesting({
    Clock? clock,
    Future<bool> Function()? localOnly,
    Future<List<String>> Function()? allowlist,
    Future<List<String>> Function()? denylist,
  }) => ScreenWatch._()
    .._clockOverride = clock
    .._localOnly = localOnly ?? PrivacyGuard.isLocalOnly
    .._allowlist = allowlist ?? WatchPolicy.allowlist
    .._denylist = denylist ?? WatchPolicy.userDenylist;

  Future<bool> Function() _localOnly = PrivacyGuard.isLocalOnly;
  Future<List<String>> Function() _allowlist = WatchPolicy.allowlist;
  Future<List<String>> Function() _denylist = WatchPolicy.userDenylist;
  bool _starting = false;
  bool _disposed = false;
  Set<String> _sessionApps = {};
  Set<String> _sessionDeny = {};
  Set<String> _normalized(List<String> apps) =>
      apps.map(WatchPolicy.normalize).toSet();

  /// Binds the scope and length before presenting the consent dialog.
  Future<WatchConsent> prepareConsent({
    Duration length = defaultSessionLength,
  }) async => WatchConsent(length, _normalized(await _allowlist()));

  Clock? _clockOverride;
  Clock get _clock => _clockOverride ?? clock;

  /// Fixed, short session lengths the UI offers (#212).
  static const sessionOptions = [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
  ];

  /// Session length when the user starts a watch without picking one.
  static const defaultSessionLength = Duration(minutes: 5);

  bool _active = false;
  DateTime? _endsAt;
  Timer? _ticker;

  /// Bumped on every [stop]. An observation op captures the generation at
  /// its start and discards its result when it changes, so a stop during an
  /// in-flight capture/inference cannot leak a post-stop result (#212).
  int _generation = 0;

  final _cancelListeners = <void Function()>[];

  /// How many times observation was refused because a hard-denied app, a
  /// private window or the lock screen was in front. The ONLY trace kept of
  /// excluded moments - app names and titles are never recorded (#212).
  int excludedCount = 0;

  /// Whether a session is currently running.
  bool get isActive => _active;

  /// The stop-generation counter (see `_generation` above).
  int get generation => _generation;

  /// Time left in the current session; zero when off.
  Duration get remaining {
    if (!_active || _endsAt == null) return Duration.zero;
    final left = _endsAt!.difference(_clock.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Starts a watching session. Returns a refusal reason, or null on start.
  ///
  /// [consentConfirmed] must come from an explicit, just-shown user consent
  /// (the consent dialog) - callers may not cache or default it.
  Future<String?> start({
    Duration length = defaultSessionLength,
    required bool consentConfirmed,
    WatchConsent? consent,
  }) async {
    if (_disposed || _active || _starting) {
      return 'A watching session is already active or starting.';
    }
    if (!consentConfirmed) {
      return 'Watching needs your explicit go-ahead for each session.';
    }
    _starting = true;
    final gen = _generation;
    try {
      if (!await _localOnly()) {
        return 'Watching works in local-only mode only - turn local-only on first.';
      }
      final apps = _normalized(await _allowlist());
      final denied = _normalized(await _denylist());
      if (gen != _generation || _disposed) {
        return 'Watching start was cancelled.';
      }
      if (apps.isEmpty) {
        return 'Pick at least one app to watch before starting.';
      }
      if (consent != null &&
          (consent.length != length || !setEquals(consent.apps, apps))) {
        return 'Watching scope changed. Review a new consent dialog.';
      }
      if (length <= Duration.zero) return 'Choose a positive session length.';
      if (!setEquals(apps, _normalized(await _allowlist()))) {
        return 'Watching scope changed. Review a new consent dialog.';
      }
      if (!await _localOnly() || gen != _generation || _disposed) {
        return 'Watching start was cancelled or local-only changed.';
      }
      _sessionApps = Set.of(consent?.apps ?? apps);
      _sessionDeny = denied;
      _active = true;
      _endsAt = _clock.now().add(length);
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (remaining <= Duration.zero) {
          stop();
        } else {
          notifyListeners();
        }
      });
      notifyListeners();
      return null;
    } finally {
      _starting = false;
    }
  }

  Future<bool> _sessionValid() async {
    if (!_active || _disposed) return false;
    final gen = _generation;
    try {
      final apps = _normalized(await _allowlist());
      final denied = _normalized(await _denylist());
      final local = await _localOnly();
      if (gen != _generation || !_active) return false;
      // Stop on tighter policy; additions never broaden this session.
      if (!local ||
          !apps.containsAll(_sessionApps) ||
          denied
              .difference(_sessionDeny)
              .intersection(_sessionApps)
              .isNotEmpty ||
          remaining <= Duration.zero) {
        stop();
        return false;
      }
    } catch (_) {
      if (gen == _generation && _active) stop();
      return false;
    }
    return true;
  }

  /// One-tap stop / kill switch (#212). Synchronous: flips state, bumps the
  /// generation so in-flight ops drop their results, and fires every
  /// registered cancel listener before returning - well under one second.
  void stop() {
    if (!_active && !_starting && _cancelListeners.isEmpty) return;
    _active = false;
    _endsAt = null;
    _ticker?.cancel();
    _ticker = null;
    _generation++;
    final listeners = List.of(_cancelListeners);
    _cancelListeners.clear();
    for (final listener in listeners) {
      listener();
    }
    notifyListeners();
  }

  /// Registers a cancel callback for an in-flight capture/inference op.
  /// Fired by [stop]; must be unregistered when the op completes.
  void registerInFlight(void Function() cancel) => _cancelListeners.add(cancel);

  /// Removes a callback registered with [registerInFlight].
  void unregisterInFlight(void Function() cancel) =>
      _cancelListeners.remove(cancel);

  /// The gate every observation op must pass first (#212).
  Future<WatchVerdict> mayObserve({
    required String frontApp,
    String? windowTitle,
    bool locked = false,
  }) async {
    if (!await _sessionValid()) return WatchVerdict.notAllowlisted;
    return WatchPolicy.verdict(
      frontApp: frontApp,
      windowTitle: windowTitle,
      locked: locked,
      allowedApps: _sessionApps.toList(),
      deniedApps: _sessionDeny.toList(),
    );
  }

  /// Runs [operation] only if the gate allows it right now. Refusals on
  /// excluded surfaces bump [excludedCount] and leave no other trace. If
  /// [stop] lands while the op is in flight, its result is discarded (#212).
  Future<T?> runIfAllowed<T>({
    required String frontApp,
    String? windowTitle,
    bool locked = false,
    required Future<T> Function() operation,
  }) async {
    // Captured before the async gate, so a stop landing DURING the check is
    // caught just like one landing mid-operation (#212).
    final gen = _generation;
    final verdict = await mayObserve(
      frontApp: frontApp,
      windowTitle: windowTitle,
      locked: locked,
    );
    if (gen != _generation || !_active) return null;
    if (verdict != WatchVerdict.allow) {
      if (verdict == WatchVerdict.hardDenied ||
          verdict == WatchVerdict.privateWindow ||
          verdict == WatchVerdict.locked) {
        excludedCount++;
        notifyListeners();
      }
      return null;
    }
    final result = await operation();
    if (!await _sessionValid()) return null;
    return gen == _generation ? result : null;
  }

  /// Clears the exclusion counter (the only session trace kept) (#212).
  void resetExcludedCount() {
    excludedCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}

/// Immutable scope shown for one consent dialog, including its duration.
class WatchConsent {
  WatchConsent(this.length, Set<String> apps) : apps = Set.unmodifiable(apps);

  /// The duration the user reviewed.
  final Duration length;

  /// The canonical apps the user reviewed.
  final Set<String> apps;
}
