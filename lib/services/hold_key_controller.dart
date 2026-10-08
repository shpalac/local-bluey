import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hold_key.dart';
import 'hold_key_bridge.dart';

/// Persisted settings for the global hold-to-talk key (#228). Off by default.
class HoldKeySettings extends ChangeNotifier {
  HoldKeySettings._();

  /// The shared settings.
  static final HoldKeySettings instance = HoldKeySettings._();

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

  /// Loads the saved choices.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
    final name = prefs.getString(_kKey);
    _key = choices.firstWhere(
      (k) => k.name == name,
      orElse: () => HoldKey.rightCommand,
    );
    final ms = prefs.getInt(_kThresholdMs) ?? 400;
    _thresholdMs = thresholds.contains(ms) ? ms : 400;
    notifyListeners();
  }

  /// Turns the shortcut on or off and saves it.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) _permissionMissing = false;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_kEnabled, value);
  }

  /// Chooses the trigger key and saves it.
  Future<void> setKey(HoldKey value) async {
    if (!choices.contains(value)) return;
    _key = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_kKey, value.name);
  }

  /// Chooses the hold length and saves it.
  Future<void> setThresholdMs(int value) async {
    if (!thresholds.contains(value)) return;
    _thresholdMs = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(_kThresholdMs, value);
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
