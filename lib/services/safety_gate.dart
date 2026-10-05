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

  static const _kEnabled = 'safety.enabled';
  static const _kAllowlist = 'safety.appAllowlist';
  static const _kResumeAt = 'safety.resumeAtMs';

  /// UI hook: describe the action, get a yes/no. Null = deny risky actions.
  Future<bool> Function(String description)? onConfirm;

  bool _killed = false;
  final _killListeners = <void Function()>[];

  bool get killed => _killed;

  void kill() {
    _killed = true;
    for (final listener in _killListeners) {
      listener();
    }
  }

  void reset() => _killed = false;

  void onKill(void Function() listener) => _killListeners.add(listener);

  /// A time-boxed pause (#133): the gate turns itself back on at this time.
  Future<DateTime?> resumeAt() async {
    final ms = (await SharedPreferences.getInstance()).getInt(_kResumeAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? true;
    if (enabled) return true;
    final resumeMs = prefs.getInt(_kResumeAt);
    if (resumeMs != null && DateTime.now().millisecondsSinceEpoch >= resumeMs) {
      // The pause expired: re-enable without waiting for the UI (#133).
      await setEnabled(true);
      return true;
    }
    return false;
  }

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
      DateTime.now().add(duration).millisecondsSinceEpoch,
    );
  }

  /// Empty = every app allowed (open_app still confirms when enabled).
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

    if (tool == 'open_app') {
      final name = (arguments['name'] as String? ?? '').toLowerCase();
      final allowed = await allowlist();
      if (allowed.isNotEmpty && !allowed.contains(name)) return false;
    }

    final description = describe(tool, arguments);
    final confirm = onConfirm;
    if (confirm == null) return false;
    return confirm(description);
  }

  static String describe(String tool, Map<String, dynamic> arguments) =>
      switch (tool) {
        'click' =>
          'Click ${arguments['target_id'] ?? 'at a spot'}'
              '${arguments['double'] == true ? ' (double)' : ''}'
              '${arguments['right'] == true ? ' (right)' : ''}',
        'type_text' =>
          'Type "${(arguments['text'] as String? ?? '').truncate(40)}"',
        'press_keys' => 'Press ${arguments['keys']}',
        'open_app' => 'Open app "${arguments['name']}"',
        'open_url' => 'Open ${arguments['url']}',
        'drag' => 'Drag on screen',
        'scroll' => 'Scroll',
        _ => tool,
      };
}

extension on String {
  String truncate(int max) => length <= max ? this : '${substring(0, max)}…';
}
