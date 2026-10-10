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

/// Callback observation state, never native recording readiness.
enum HoldKeyActionStatus { dispatched, completed, failed }

/// Safe latest dispatched callback result without raw exception details.
class HoldKeyActionResult {
  /// Identifies the action and observation status.
  const HoldKeyActionResult(this.action, this.status);

  /// Dispatched recorder action, not a confirmed native recording state.
  final HoldKeyAction action;

  /// Whether the callback is pending, completed or failed.
  final HoldKeyActionStatus status;

  /// Generic failure text; no endpoint, path or plugin details.
  String? get error => status == HoldKeyActionStatus.failed
      ? 'Hold-key action could not be completed. Try again.'
      : null;
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

  /// Current observed action result, cleared on changed desired state/disposal.
  final ValueNotifier<HoldKeyActionResult?> actionResult = ValueNotifier(null);
  int _actionRevision = 0;
  HoldKeyBridge? _bridge;
  HoldKey? _runningKey;
  int? _runningThreshold;
  bool _active = false;
  bool _disposed = false;
  bool _recording = false;
  bool _cleanupPending = false;
  int _generation = 0;
  (bool, HoldKey, int)? _desired;
  Future<void>? _tail;
  Future<void>? _pendingSync;

  /// Whether the currently owned bridge reports enabled, even during cleanup.
  bool get running => _bridge?.enabled ?? false;

  /// A disable outcome is unresolved or failed. No stopped guarantee.
  bool get cleanupPending => _cleanupPending;

  (bool, HoldKey, int) get _snapshot =>
      (supported && settings.enabled, settings.key, settings.thresholdMs);

  bool _current(int generation, (bool, HoldKey, int) desired) =>
      !_disposed && generation == _generation && desired == _snapshot;

  Future<void> _enqueue(Future<void> Function() action) {
    final next = (_tail ?? Future<void>.value()).then((_) => action());
    final settled = next.catchError((_) {});
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return next;
  }

  /// Coalesces equal entered requests; changed desired state invalidates old work.
  Future<void> sync() {
    if (_disposed) return Future<void>.value();
    final desired = _snapshot;
    if (_desired == desired && _pendingSync != null) return _pendingSync!;
    if (_desired != desired) {
      _desired = desired;
      _generation++;
      _active = false;
      _actionRevision++;
      actionResult.value = null;
    }
    final generation = _generation;
    final next = _enqueue(() => _transition(generation, desired));
    _pendingSync = next;
    next.then(
      (_) {
        if (identical(_pendingSync, next)) _pendingSync = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_pendingSync, next)) _pendingSync = null;
      },
    );
    return next;
  }

  Future<void> _transition(int generation, (bool, HoldKey, int) desired) async {
    if (!_current(generation, desired)) return;
    final (wanted, key, threshold) = desired;
    if (_bridge != null &&
        (!wanted ||
            _cleanupPending ||
            _runningKey != key ||
            _runningThreshold != threshold)) {
      await _stop();
    }
    if (!_current(generation, desired) || !wanted) return;
    if (_bridge != null) {
      _active = true;
      return;
    }
    late final HoldKeyBridge bridge;
    try {
      bridge = _createBridge(
        HoldKeyMachine(
          key: key,
          threshold: Duration(milliseconds: threshold),
        ),
        (action) => _handle(bridge, action),
      );
    } catch (_) {
      throw const HoldKeyControllerException();
    }
    _bridge = bridge;
    _runningKey = key;
    _runningThreshold = threshold;
    try {
      final allowed = await bridge.hasPermission();
      if (!_current(generation, desired)) {
        await _stop();
        return;
      }
      if (!allowed) {
        await bridge.requestPermission();
        if (!_current(generation, desired)) {
          await _stop();
          return;
        }
      }
      final enabled = await bridge.enable();
      if (!_current(generation, desired)) {
        await _stop();
        return;
      }
      if (enabled) {
        _active = true;
        settings.markPermissionMissing(false);
      } else {
        await _stop();
        if (_current(generation, desired)) settings.markPermissionMissing(true);
      }
    } catch (_) {
      // Failed cleanup retains the exact candidate for explicit later retry.
      if (!_cleanupPending) await _stop();
      throw const HoldKeyControllerException();
    }
  }

  /// Sleep, lock or the kill switch: cancel an entered hold, never send it.
  void reset() => _bridge?.reset();

  /// Invalidates immediately, then waits for entered candidate cleanup.
  /// Calling dispose again explicitly retries a failed disable.
  Future<void> dispose() {
    _disposed = true;
    _generation++;
    _active = false;
    _actionRevision++;
    actionResult.value = null;
    return _enqueue(_stop);
  }

  Future<void> _stop() async {
    final bridge = _bridge;
    if (bridge == null) return;
    _active = false;
    _cleanupPending = true;
    try {
      // Cancel an owned recording even when resource disable later fails.
      bridge.reset();
      await bridge.disable();
    } catch (_) {
      throw const HoldKeyControllerException();
    }
    _bridge = null;
    _runningKey = null;
    _runningThreshold = null;
    _cleanupPending = false;
    // Fake/native bridges may not emit reset cancellation themselves.
    if (_recording) {
      _recording = false;
      _dispatch(bridge, HoldKeyAction.cancel, onCancel);
    }
  }

  void _dispatch(
    HoldKeyBridge bridge,
    HoldKeyAction action,
    Future<void> Function() callback,
  ) {
    final revision = ++_actionRevision;
    final generation = _generation;
    final desired = _snapshot;
    bool current() =>
        !_disposed &&
        revision == _actionRevision &&
        generation == _generation &&
        desired == _snapshot &&
        (identical(_bridge, bridge) ||
            (_bridge == null && action == HoldKeyAction.cancel));
    void publish(HoldKeyActionStatus status) {
      if (current()) actionResult.value = HoldKeyActionResult(action, status);
    }

    publish(HoldKeyActionStatus.dispatched);
    // A result listener can synchronously replace/dispose the owner.
    if (action != HoldKeyAction.cancel && !current()) return;
    // Invoke immediately to preserve existing action delivery/timing. Observe all
    // completions, including old or disposed failures, without retrying effects.
    try {
      final result = callback();
      result.then(
        (_) => publish(HoldKeyActionStatus.completed),
        onError: (Object _, StackTrace _) =>
            publish(HoldKeyActionStatus.failed),
      );
    } catch (_) {
      publish(HoldKeyActionStatus.failed);
    }
  }

  void _handle(HoldKeyBridge bridge, HoldKeyAction action) {
    if (!identical(_bridge, bridge)) return;
    if (action == HoldKeyAction.cancel && _recording) {
      _recording = false;
      _dispatch(bridge, HoldKeyAction.cancel, onCancel);
      return;
    }
    if (!_active || _disposed || _desired != _snapshot) return;
    switch (action) {
      case HoldKeyAction.start:
        _recording = true;
        _dispatch(bridge, action, onStart);
      case HoldKeyAction.send:
        _recording = false;
        _dispatch(bridge, action, onSend);
      case HoldKeyAction.cancel:
        _dispatch(bridge, HoldKeyAction.cancel, onCancel);
      case HoldKeyAction.none:
        break;
    }
  }
}

/// Generic controller operation failure; cleanup remains owned when uncertain.
class HoldKeyControllerException implements Exception {
  /// Creates a safe controller failure.
  const HoldKeyControllerException();
  @override
  String toString() => 'Hold-key listener could not be updated or stopped.';
}
