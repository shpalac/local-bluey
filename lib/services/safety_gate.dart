import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Decides whether a tool call may run. Safe tools always run; risky ones
/// need a human yes through [onConfirm] (wired to a dialog on the Mac).
/// A global kill switch cancels everything in flight.
class SafetyGate {
  SafetyGate({this.onConfirm});

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

  /// UI hook: describe the action, get a yes/no. Null = deny risky actions.
  Future<bool> Function(String description)? onConfirm;

  bool _killed = false;

  /// Bumped on every [kill]. A running tool loop captures the generation at
  /// its start and stops when it changes, so a kill + resume cannot revive
  /// a run that was already cancelled (#107).
  int _generation = 0;

  final _killListeners = <void Function()>[];

  bool get killed => _killed;
  int get generation => _generation;

  void kill() {
    _killed = true;
    _generation++;
    for (final listener in _killListeners) {
      listener();
    }
  }

  void reset() => _killed = false;

  void onKill(void Function() listener) => _killListeners.add(listener);

  Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? true;

  Future<void> setEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_kEnabled, value);

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

  Future<void> setAllowlist(Set<String> apps) async =>
      (await SharedPreferences.getInstance()).setString(
        _kAllowlist,
        apps.join(','),
      );

  /// True when the tool call may execute.
  Future<bool> authorize(String tool, Map<String, dynamic> arguments) async {
    if (_killed) return false;
    if (!await isEnabled()) return true;
    if (!riskyTools.contains(tool)) return true;

    final allowed = await allowlist();
    // open_app targets the named app; every other risky tool targets
    // whatever is in front right now (#109).
    var targetApp = tool == 'open_app'
        ? (arguments['name'] as String? ?? '').toLowerCase()
        : (frontAppProvider?.call() ?? '').toLowerCase();
    if (targetApp.isNotEmpty) {
      if (defaultDenyApps.contains(targetApp) && !allowed.contains(targetApp)) {
        return false;
      }
      if (allowed.isNotEmpty && !allowed.contains(targetApp)) return false;
    }

    final description = describe(tool, arguments);
    final confirm = onConfirm;
    if (confirm == null) return false;
    final ok = await confirm(description);
    // A kill while the confirmation dialog was open must still win (#107).
    if (_killed) return false;
    return ok;
  }

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
