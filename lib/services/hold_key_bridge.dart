import 'dart:async';

import 'package:flutter/services.dart';

import 'hold_key.dart';

/// Connects the native system-wide key listener to [HoldKeyMachine] (#228).
///
/// Off until [enable] succeeds. The native side refuses without the Input
/// Monitoring permission, in which case [enable] returns false and nothing
/// listens. The owner decides what each [HoldKeyAction] does (start, send or
/// cancel a recording) through [onAction].
class HoldKeyBridge {
  /// Creates a bridge around [machine]. The channels and clock can be
  /// replaced in tests.
  HoldKeyBridge({
    required this.machine,
    required this.onAction,
    MethodChannel? method,
    Stream<dynamic>? events,
    DateTime Function()? now,
    this.tickEvery = const Duration(milliseconds: 50),
  }) : _method = method ?? const MethodChannel('local_bluey/holdkey'),
       _events =
           events ??
           const EventChannel('local_bluey/holdkey/events')
               .receiveBroadcastStream(),
       _now = now ?? DateTime.now;

  /// The state machine that decides what a key hold means.
  final HoldKeyMachine machine;

  /// Called for every start, send and cancel the machine produces.
  final void Function(HoldKeyAction action) onAction;

  /// How often the machine is polled while enabled.
  final Duration tickEvery;

  final MethodChannel _method;
  final Stream<dynamic> _events;
  final DateTime Function() _now;

  StreamSubscription<dynamic>? _subscription;
  Timer? _timer;

  /// Whether the listener is on.
  bool get enabled => _subscription != null;

  /// Whether the Input Monitoring permission is granted. Never prompts.
  Future<bool> hasPermission() async =>
      await _method.invokeMethod<bool>('permission') ?? false;

  /// Shows the system permission prompt. Returns the new state.
  Future<bool> requestPermission() async =>
      await _method.invokeMethod<bool>('requestPermission') ?? false;

  /// Starts listening. Returns false, and stays off, when the permission is
  /// missing or the native side fails.
  Future<bool> enable() async {
    if (enabled) return true;
    bool started;
    try {
      started = await _method.invokeMethod<bool>('start') ?? false;
    } on PlatformException {
      started = false;
    } on MissingPluginException {
      started = false;
    }
    if (!started) return false;
    _subscription = _events.listen(_onEvent, onError: (_) => disable());
    _timer = Timer.periodic(tickEvery, (_) => tick());
    return true;
  }

  /// Stops listening. A running recording is cancelled, never sent.
  Future<void> disable() async {
    await _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
    _timer = null;
    _emit(machine.reset());
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException {
      // Already stopped is fine.
    } on MissingPluginException {
      // No native side, nothing to stop.
    }
  }

  /// Sleep, lock, app deactivate or the kill switch: cancel any hold.
  void reset() => _emit(machine.reset());

  /// Polls the machine. Called by the timer; public for tests.
  void tick() => _emit(machine.tick(_now()));

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'];
    final key = _keyFor(event['key']);
    final now = _now();
    switch (type) {
      case 'down':
        _emit(machine.keyDown(key, now));
      case 'up':
        _emit(machine.keyUp(key, now));
      case 'escape':
        _emit(machine.escape(now));
    }
  }

  static HoldKey _keyFor(Object? name) {
    for (final key in HoldKey.values) {
      if (key.name == name) return key;
    }
    return HoldKey.other;
  }

  void _emit(HoldKeyAction action) {
    if (action != HoldKeyAction.none) onAction(action);
  }
}
