import 'package:clock/clock.dart';

import 'request_interfaces.dart';

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Decides whether a tool call may run. Safe tools always run; risky ones
/// need a human yes through [onConfirm] (wired to a dialog on the Mac).
/// A global kill switch cancels everything in flight.
class SafetyGate implements GateLike {
  SafetyGate({this.onConfirm, Clock? clock}) : _clockOverride = clock;

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

  static const _kEnabled = 'safety.enabled';
  static const _kAllowlist = 'safety.appAllowlist';
  static const _kResumeAt = 'safety.resumeAtMs';

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

  /// A time-boxed pause (#133): the gate turns itself back on at this time.
  Future<DateTime?> resumeAt() async {
    final ms = (await SharedPreferences.getInstance()).getInt(_kResumeAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Whether the gate currently asks for confirmations. An expired
  /// time-boxed pause re-enables it on read (#133).
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? true;
    if (enabled) return true;
    final resumeMs = prefs.getInt(_kResumeAt);
    if (resumeMs != null && _clock.now().millisecondsSinceEpoch >= resumeMs) {
      // The pause expired: re-enable without waiting for the UI (#133).
      await setEnabled(true);
      return true;
    }
    return false;
  }

  /// Turns confirmations on or off; turning on clears any pause deadline.
  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
    if (value) await prefs.remove(_kResumeAt);
  }

  /// Disables the gate until [duration] has passed (#133).
  Future<void> pauseFor(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
    await prefs.setInt(
      _kResumeAt,
      _clock.now().add(duration).millisecondsSinceEpoch,
    );
  }

  /// Empty = every app allowed except [defaultDenyApps] (#109).
  Future<Set<String>> allowlist() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_kAllowlist) ?? '';
    return raw
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  /// Replaces the allowlist. Values are lowercased app names.
  Future<void> setAllowlist(Set<String> apps) async =>
      (await SharedPreferences.getInstance()).setString(
        _kAllowlist,
        apps.join(','),
      );

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
