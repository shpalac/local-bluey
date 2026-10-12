import 'dart:collection';

import 'activity_step.dart';

/// BLU-004 groundwork: bounded, ephemeral activity storage.
///
/// This is deliberately NOT the encrypted SQLite implementation. ADR-001
/// requires memory-only data until an independently verified encrypted
/// database, WAL/journal cleanup and key lifecycle exist. No filesystem,
/// database, preference or network API is reachable through this store.
final class ActivityStore {
  ActivityStore.memoryOnly({
    DateTime Function()? now,
    this.capacity = 500,
    this.retention = const Duration(days: 7),
    this.sessionLength = const Duration(minutes: 5),
  }) : _now = now ?? DateTime.now {
    if (capacity < 1 ||
        retention <= Duration.zero ||
        sessionLength <= Duration.zero) {
      throw ArgumentError(
        'capacity and retention/session durations must be positive',
      );
    }
  }

  final int capacity;
  final Duration retention;
  final Duration sessionLength;
  final DateTime Function() _now;
  final LinkedHashMap<String, ActivityStep> _entries = LinkedHashMap();
  DateTime? _sessionEndsAt;
  bool _disposed = false;

  /// Explicit consent is required for each session. No state is persisted.
  bool startSession({required bool consentConfirmed}) {
    _expireSession();
    if (_disposed || !consentConfirmed || _sessionEndsAt != null) return false;
    _entries.clear();
    _sessionEndsAt = _now().toUtc().add(sessionLength);
    return true;
  }

  bool get isActive {
    _expireSession();
    return _sessionEndsAt != null;
  }

  /// Refuse unapproved, expired, future and duplicate steps without side effects.
  /// A caller must pass its *current* SafetyGate/privacy approval; the store
  /// cannot make a sensitive-window classification by itself.
  bool add(ActivityStep step, {required bool approved}) {
    _expireSession();
    if (_disposed || !approved || _sessionEndsAt == null) return false;
    final now = _now().toUtc();
    if (step.timestamp.isAfter(now) ||
        !step.timestamp.isAfter(now.subtract(retention)) ||
        _entries.containsKey(step.stepId)) {
      return false;
    }
    _prune(now);
    _entries[step.stepId] = step;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return true;
  }

  /// Read a non-live immutable snapshot; never return the mutable buffer.
  List<ActivityStep> get snapshot {
    _expireSession();
    if (_sessionEndsAt == null) return const [];
    _prune(_now().toUtc());
    return List<ActivityStep>.unmodifiable(_entries.values);
  }

  /// Physical memory purge; no future auto-resume.
  void stopSession() {
    _sessionEndsAt = null;
    _entries.clear();
  }

  /// Retention/deletion integration may call this without starting a session.
  Future<void> clear() async => _entries.clear();

  void dispose() {
    stopSession();
    _disposed = true;
  }

  void _expireSession() {
    final until = _sessionEndsAt;
    if (until != null && !_now().toUtc().isBefore(until)) {
      stopSession();
    }
  }

  void _prune(DateTime now) {
    _entries.removeWhere(
      (_, step) => !step.timestamp.isAfter(now.subtract(retention)),
    );
  }
}
