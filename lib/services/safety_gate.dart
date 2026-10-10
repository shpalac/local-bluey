import 'package:clock/clock.dart';

import 'request_interfaces.dart';

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Safe failure from safety preference reads or mutations.
class SafetyStorageException implements Exception {
  /// Creates a failure without raw plugin data.
  const SafetyStorageException();
  @override
  String toString() => 'Safety preferences could not be updated.';
}

/// Shared ordered preference owner; kill state remains local to SafetyGate.
class SafetyPreferences {
  SafetyPreferences._()
    : _read = (() async {
        final prefs = await SharedPreferences.getInstance();
        return {
          for (final key in [_enabled, _allowlist, _resume])
            key: prefs.get(key),
        };
      }),
      _write = ((key, value) async {
        final prefs = await SharedPreferences.getInstance();
        if (value is bool) return prefs.setBool(key, value);
        if (value is int) return prefs.setInt(key, value);
        return prefs.setString(key, value as String);
      }),
      _remove = ((key) async =>
          (await SharedPreferences.getInstance()).remove(key));

  /// Actual storage-operation seams for isolated synthetic tests.
  @visibleForTesting
  SafetyPreferences.forTest({
    required this._read,
    required this._write,
    required this._remove,
  });

  /// Production preference owner shared by all gates and registry deletion.
  static final SafetyPreferences instance = SafetyPreferences._();
  static const _enabled = 'safety.enabled',
      _allowlist = 'safety.appAllowlist',
      _resume = 'safety.resumeAtMs';
  final Future<Map<String, Object?>> Function() _read;
  final Future<bool> Function(String, Object) _write;
  final Future<bool> Function(String) _remove;
  Future<void>? _io;
  int _revision = 0;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    Future<T> invoke() async {
      try {
        return await operation();
      } catch (_) {
        throw const SafetyStorageException();
      }
    }

    final previous = _io;
    final next = previous == null ? invoke() : previous.then((_) => invoke());
    final settled = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _io = settled;
    settled.then((_) {
      if (identical(_io, settled)) _io = null;
    });
    return next;
  }

  Future<void> _put(String key, Object value) async {
    if (!await _write(key, value)) throw const SafetyStorageException();
  }

  Future<void> _delete(String key) async {
    if (!await _remove(key)) throw const SafetyStorageException();
  }

  /// Reads the retained deadline in storage order.
  Future<DateTime?> resumeAt() => _enqueue(() async {
    final ms = (await _read())[_resume] as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  });

  /// Reads current policy; an older expiry cannot overwrite a newer intent.
  Future<bool> isEnabled(DateTime Function() now) {
    final revision = _revision;
    return _enqueue(() async {
      final prefs = Map<String, Object?>.of(await _read());
      if (revision != _revision) return true; // Never bypass on stale policy.
      final enabled = prefs[_enabled] as bool? ?? true;
      if (enabled) return true;
      final deadline = prefs[_resume] as int?;
      if (deadline != null && now().millisecondsSinceEpoch >= deadline) {
        if (revision != _revision) return true; // conservative stale read
        await _put(_enabled, true);
        // A newer explicit choice may have entered while this setter waited.
        // It is queued after this read and owns the final storage state.
        await _delete(_resume);
        return true;
      }
      return false;
    });
  }

  /// Explicit user choice, serialized against all gates and clears.
  Future<void> setEnabled(bool value) {
    _revision++;
    return _enqueue(() async {
      await _put(_enabled, value);
      if (value) await _delete(_resume);
    });
  }

  /// Writes the deadline before disabling, so a failed deadline write cannot
  /// create a new indefinite disabled state. Partial success is not rollback.
  Future<void> pauseFor(Duration duration, DateTime Function() now) {
    _revision++;
    return _enqueue(() async {
      await _put(_resume, now().add(duration).millisecondsSinceEpoch);
      await _put(_enabled, false);
    });
  }

  /// Reads the actual retained allowlist in storage order.
  Future<Set<String>> allowlist() => _enqueue(() async {
    final raw = (await _read())[_allowlist] as String? ?? '';
    return raw
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  });

  /// Snapshots and writes a fresh allowlist choice.
  Future<void> setAllowlist(Set<String> apps) {
    final raw = Set<String>.of(apps).join(',');
    _revision++;
    return _enqueue(() => _put(_allowlist, raw));
  }

  /// Explicit preference deletion only; does not alter any gate's kill state.
  Future<void> clear() {
    _revision++;
    return _enqueue(() async {
      await _delete(_enabled);
      await _delete(_allowlist);
      await _delete(_resume);
    });
  }
}

/// Decides whether a tool call may run. Safe tools always run; risky ones
/// need a human yes through [onConfirm] (wired to a dialog on the Mac).
/// A global kill switch cancels everything in flight.
class SafetyGate implements GateLike {
  SafetyGate({this.onConfirm, Clock? clock, SafetyPreferences? preferences})
    : _clockOverride = clock,
      _preferences = preferences ?? SafetyPreferences.instance;
  final SafetyPreferences _preferences;

  /// Injectable clock for tests (#136); falls back to the zone-aware
  /// package:clock so fakeAsync controls time in tests.
  final Clock? _clockOverride;
  Clock get _clock => _clockOverride ?? clock;

  /// Tools that change the user's machine state and therefore ask first.
  static const riskyTools = {
    'click',
    'type_text',
    'press_keys',
    'open_app',
    'open_url',
    'drag',
    'scroll',
  };

  /// Apps that are denied by default even with an empty allowlist (#109):
  /// shells and system surfaces where a blind agent can do real damage.
  /// Listing one explicitly in the allowlist re-allows it.
  static const defaultDenyApps = {
    'terminal',
    'iterm',
    'iterm2',
    'keychain access',
    'system settings',
    'system preferences',
  };

  /// Input tools act on whatever app is in front, so the allowlist must
  /// cover them too (#109). Wired from the executor's last snapshot.
  String Function()? frontAppProvider;

  /// UI hook: describe the action, get a yes/no. Null = deny risky actions.
  Future<bool> Function(String description)? onConfirm;

  bool _killed = false;

  /// Bumped on every [kill]. A running tool loop captures the generation at
  /// its start and stops when it changes, so a kill + resume cannot revive
  /// a run that was already cancelled (#107).
  int _generation = 0;

  final _killListeners = <void Function()>[];
  bool _dispatchingKill = false;
  int _killListenerFailures = 0;

  /// Cumulative failed kill callbacks, without their errors or private contents.
  /// Later listeners still receive the same dispatch.
  int get killListenerFailures => _killListenerFailures;

  @override
  bool get killed => _killed;
  @override
  int get generation => _generation;

  /// Engages the kill switch: every [authorize] call denies, and running
  /// tool loops polling [generation] stop (#107). Repeated calls notify again;
  /// reentrant calls update state/generation without recursively dispatching.
  /// Listener failures are isolated and counted in [killListenerFailures].
  void kill() {
    _killed = true;
    _generation++;
    // Reentrant kill still invalidates work but does not recursively dispatch.
    // A separate later kill dispatches again, including newly added listeners.
    if (_dispatchingKill) return;
    _dispatchingKill = true;
    try {
      for (final listener in List<void Function()>.of(_killListeners)) {
        try {
          listener();
        } catch (_) {
          _killListenerFailures++;
        }
      }
    } finally {
      _dispatchingKill = false;
    }
  }

  /// Lifts the kill switch so new actions can be confirmed again.
  void reset() => _killed = false;

  /// Registers for the next kill dispatch. Each dispatch snapshots listeners;
  /// additions during delivery begin next time. Exceptions are counted and
  /// isolated. Reentrant kills invalidate generation but do not recurse.
  void onKill(void Function() listener) => _killListeners.add(listener);

  /// Retained pause deadline.
  Future<DateTime?> resumeAt() => _preferences.resumeAt();

  /// Confirmation state, with ordered clock expiry.
  Future<bool> isEnabled() => _preferences.isEnabled(() => _clock.now());

  /// Explicit toggle choice; enabling removes any deadline.
  Future<void> setEnabled(bool value) => _preferences.setEnabled(value);

  /// Time-boxed pause using this gate's injected clock.
  Future<void> pauseFor(Duration duration) =>
      _preferences.pauseFor(duration, () => _clock.now());

  /// Empty means every app except the default deny list.
  Future<Set<String>> allowlist() => _preferences.allowlist();

  /// Replaces allowed app names.
  Future<void> setAllowlist(Set<String> apps) =>
      _preferences.setAllowlist(apps);

  /// Explicit local preference clear, preserving kill/generation/listeners.
  Future<void> clearPreferences() => _preferences.clear();

  /// True when the tool call may execute. Captures kill generation before
  /// reads; kill/reset cannot revive entered authorization. Stale read or
  /// confirmation errors deny quietly; current errors still propagate.
  @override
  Future<bool> authorize(String tool, Map<String, dynamic> arguments) async {
    if (_killed) return false;
    final gen = _generation;
    bool stale() => _killed || gen != _generation;
    try {
      final enabled = await isEnabled();
      if (stale()) return false;
      if (!enabled) return true;
      if (!riskyTools.contains(tool)) return true;

      final allowed = await allowlist();
      if (stale()) return false;
      // open_app targets the named app; every other risky tool targets
      // whatever is in front right now (#109).
      var targetApp = tool == 'open_app'
          ? (arguments['name'] as String? ?? '').toLowerCase()
          : (frontAppProvider?.call() ?? '').toLowerCase();
      if (targetApp.isNotEmpty) {
        if (defaultDenyApps.contains(targetApp) &&
            !allowed.contains(targetApp)) {
          return false;
        }
        if (allowed.isNotEmpty && !allowed.contains(targetApp)) return false;
      }

      final description = describe(tool, arguments);
      final confirm = onConfirm;
      if (confirm == null || stale()) return false;
      final ok = await confirm(description);
      // A kill while the confirmation dialog was open must still win (#107).
      if (stale()) return false;
      return ok;
    } catch (_) {
      if (stale()) return false;
      rethrow;
    }
  }

  /// Human-readable one-liner for a tool call, shown in the confirmation
  /// dialog (e.g. `click "Save" at (412, 300)`).
  static String describe(
    String tool,
    Map<String, dynamic> arguments,
  ) => switch (tool) {
    'click' => _describeClick(arguments),
    'type_text' => _describeType(arguments),
    'press_keys' => 'Press ${arguments['keys'] ?? '(no keys specified)'}',
    'open_app' => 'Open app "${arguments['name']}"',
    'open_url' => 'Open ${arguments['url']}',
    'drag' => 'Drag on screen',
    'scroll' =>
      'Scroll ${arguments['direction'] ?? ''}'
              '${arguments['amount'] != null ? ' x${arguments['amount']}' : ''}'
          .trim(),
    _ => tool,
  };

  static String _describeClick(Map<String, dynamic> arguments) {
    final id = arguments['target_id'];
    final where = id != null
        ? '$id'
        : 'at (${arguments['x']}, ${arguments['y']})';
    return 'Click $where'
        '${arguments['double'] == true ? ' (double)' : ''}'
        '${arguments['right'] == true ? ' (right)' : ''}';
  }

  /// The whole point of the dialog is that the human sees what will happen
  /// (#108): show the full text for short payloads, and for long ones show
  /// BOTH ends plus the total length so a destructive tail cannot hide.
  static String _describeType(Map<String, dynamic> arguments) {
    final text = arguments['text'] as String? ?? '';
    final String shown;
    if (text.length <= 200) {
      shown = '"$text"';
    } else {
      shown =
          '"${text.substring(0, 100)} … ${text.substring(text.length - 100)}"'
          ' (${text.length} characters total)';
    }
    final returns = arguments['press_return'] == true
        ? ' and press Return'
        : '';
    return 'Type $shown$returns';
  }
}
