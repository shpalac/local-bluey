import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hold_key.dart';
import 'hold_key_bridge.dart';

/// Generic preference failure, no raw details or rollback claim.
class HoldKeyStorageException implements Exception {
  /// Creates a safe storage failure.
  const HoldKeyStorageException();
  @override
  String toString() => 'Hold-key preferences could not be verified or updated.';
}

/// Persisted settings for the global hold-to-talk key (#228). Off by default.
class HoldKeySettings extends ChangeNotifier {
  /// Uses preferences by default or injected actual operations for fixtures.
  HoldKeySettings({
    Future<Object?> Function(String)? read,
    Future<bool> Function(String, Object)? write,
    Future<bool> Function(String)? remove,
  }) : _read =
           read ??
           ((key) async => (await SharedPreferences.getInstance()).get(key)),
       _write =
           write ??
           ((key, value) async {
             final prefs = await SharedPreferences.getInstance();
             if (value is bool) return prefs.setBool(key, value);
             if (value is int) return prefs.setInt(key, value);
             return prefs.setString(key, value as String);
           }),
       _remove =
           remove ??
           ((key) async => (await SharedPreferences.getInstance()).remove(key));

  static final _instance = HoldKeySettings();

  /// Isolated owner used by registry and section fixtures.
  @visibleForTesting
  static HoldKeySettings? debugOverride;

  /// Shared preference owner.
  static HoldKeySettings get instance => debugOverride ?? _instance;
  final Future<Object?> Function(String) _read;
  final Future<bool> Function(String, Object) _write;
  final Future<bool> Function(String) _remove;
  Future<void>? _tail;
  int _revision = 0;
  int _clearEpoch = 0;
  bool _verified = false;

  /// Whether the retained snapshot is currently source-verified.
  bool get verified => _verified;

  static const _kEnabled = 'holdkey.enabled';
  static const _kKey = 'holdkey.key';
  static const _kThresholdMs = 'holdkey.thresholdMs';

  /// Keys offered in Settings.
  static const choices = [
    HoldKey.rightCommand,
    HoldKey.leftCommand,
    HoldKey.rightOption,
    HoldKey.fn,
  ];

  /// Hold lengths offered in Settings, in milliseconds.
  static const thresholds = [300, 400, 600];

  bool _enabled = false;
  HoldKey _key = HoldKey.rightCommand;
  int _thresholdMs = 400;
  bool _permissionMissing = false;

  /// Whether the shortcut is on. Default false.
  bool get enabled => _enabled;

  /// The trigger key. Default Right Command.
  HoldKey get key => _key;

  /// How long the key must be held, in milliseconds. Default 400.
  int get thresholdMs => _thresholdMs;

  /// True when the shortcut is on but macOS has not granted Input Monitoring.
  bool get permissionMissing => _permissionMissing;

  Future<void> _publishStored(int revision, bool resetPermission) async {
    final enabled = (await _read(_kEnabled)) as bool? ?? false;
    final name = (await _read(_kKey)) as String?;
    final ms = (await _read(_kThresholdMs)) as int? ?? 400;
    if (revision != _revision) return;
    _enabled = enabled;
    _key = choices.firstWhere(
      (k) => k.name == name,
      orElse: () => HoldKey.rightCommand,
    );
    _thresholdMs = thresholds.contains(ms) ? ms : 400;
    _verified = true;
    if (resetPermission && !enabled) _permissionMissing = false;
    notifyListeners();
  }

  Future<void> _enqueue(
    Future<void> Function() action, {
    bool resetPermission = false,
  }) {
    final revision = ++_revision;
    final next = (_tail ?? Future<void>.value()).then((_) async {
      try {
        await action();
        await _publishStored(revision, resetPermission);
      } catch (_) {
        if (revision == _revision) {
          try {
            await _publishStored(revision, resetPermission);
          } catch (_) {
            if (revision == _revision) {
              _verified = false;
              notifyListeners();
            }
          }
        }
        throw const HoldKeyStorageException();
      }
    });
    final settled = next.catchError((_) {});
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return next;
  }

  /// Loads one coherent snapshot in storage order.
  Future<void> load() => _enqueue(() async {});

  Future<void> _set(String key, Object value) {
    final epoch = _clearEpoch;
    return _enqueue(() async {
      if (epoch != _clearEpoch) return;
      if (!await _write(key, value)) throw const HoldKeyStorageException();
    }, resetPermission: key == _kEnabled && value == false);
  }

  /// Persists before publishing shortcut state.
  Future<void> setEnabled(bool value) => _set(_kEnabled, value);

  /// Persists a valid key; invalid input remains a no-op.
  Future<void> setKey(HoldKey value) =>
      choices.contains(value) ? _set(_kKey, value.name) : Future<void>.value();

  /// Persists a valid hold length; invalid input remains a no-op.
  Future<void> setThresholdMs(int value) => thresholds.contains(value)
      ? _set(_kThresholdMs, value)
      : Future<void>.value();

  /// Orders explicit three-key deletion and reconciles actual partial failure.
  Future<void> clear() {
    _clearEpoch++;
    return _enqueue(() async {
      for (final key in [_kEnabled, _kKey, _kThresholdMs]) {
        if (!await _remove(key)) throw const HoldKeyStorageException();
      }
    }, resetPermission: true);
  }

  /// Set by the controller when the permission check fails.
  void markPermissionMissing(bool missing) {
    if (_permissionMissing == missing) return;
    _permissionMissing = missing;
    notifyListeners();
  }
}

/// Starts and stops the listener to match [HoldKeySettings] and turns its
/// actions into recorder calls.
class HoldKeyController {
  /// Creates a controller. [createBridge] is replaced in tests.
  HoldKeyController({
    required this.settings,
    required this.onStart,
    required this.onSend,
    required this.onCancel,
    this.supported = true,
    HoldKeyBridge Function(
      HoldKeyMachine machine,
      void Function(HoldKeyAction) onAction,
    )?
    createBridge,
  }) : _createBridge =
           createBridge ??
           ((machine, onAction) =>
               HoldKeyBridge(machine: machine, onAction: onAction));

  /// The settings this controller follows.
  final HoldKeySettings settings;

  /// Recording should start (the key was held alone long enough).
  final Future<void> Function() onStart;

  /// Recording should stop and be sent.
  final Future<void> Function() onSend;

  /// Recording should stop and be discarded.
  final Future<void> Function() onCancel;

  /// False on platforms with no native listener (everything but macOS).
  final bool supported;

  final HoldKeyBridge Function(
    HoldKeyMachine machine,
    void Function(HoldKeyAction) onAction,
  )
  _createBridge;

  HoldKeyBridge? _bridge;
  HoldKey? _runningKey;
  int? _runningThreshold;

  /// Whether the listener is currently on.
  bool get running => _bridge?.enabled ?? false;

  /// Brings the listener in line with the settings. Call after any change.
  Future<void> sync() async {
    final wanted = supported && settings.enabled;
    final changed =
        _runningKey != settings.key ||
        _runningThreshold != settings.thresholdMs;
    if (!wanted || (_bridge != null && changed)) {
      await _stop();
    }
    if (!wanted || _bridge != null) return;
    final bridge = _createBridge(
      HoldKeyMachine(
        key: settings.key,
        threshold: Duration(milliseconds: settings.thresholdMs),
      ),
      _handle,
    );
    if (!await bridge.hasPermission()) {
      await bridge.requestPermission();
    }
    if (await bridge.enable()) {
      _bridge = bridge;
      _runningKey = settings.key;
      _runningThreshold = settings.thresholdMs;
      settings.markPermissionMissing(false);
    } else {
      settings.markPermissionMissing(true);
    }
  }

  /// Sleep, lock or the kill switch: cancel any hold in progress.
  void reset() => _bridge?.reset();

  /// Stops the listener.
  Future<void> dispose() => _stop();

  Future<void> _stop() async {
    final bridge = _bridge;
    _bridge = null;
    _runningKey = null;
    _runningThreshold = null;
    await bridge?.disable();
  }

  void _handle(HoldKeyAction action) {
    switch (action) {
      case HoldKeyAction.start:
        onStart();
      case HoldKeyAction.send:
        onSend();
      case HoldKeyAction.cancel:
        onCancel();
      case HoldKeyAction.none:
        break;
    }
  }
}
