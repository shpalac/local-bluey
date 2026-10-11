import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

enum WindowIntent { show, hide }

/// Explicit local completion only, never verified native window state.
class WindowActionCaller extends ChangeNotifier {
  WindowActionCaller()
    : this.operations(
        show: () => windowManager.show(),
        focus: () => windowManager.focus(),
        hide: () => windowManager.hide(),
      );
  WindowActionCaller.operations({
    required Future<void> Function() show,
    required Future<void> Function() focus,
    required Future<void> Function() hide,
  }) : this._operations(show, focus, hide);
  WindowActionCaller._operations(this._show, this._focus, this._hide);
  final Future<void> Function() _show, _focus, _hide;
  Future<void>? _pending;
  WindowIntent? _desired, _entered, _failed;
  bool _disposed = false, _notifierDisposed = false;
  int _notifyDepth = 0;
  bool get loading => _pending != null;
  WindowIntent? get failed => _failed;
  bool get visible => loading || failed != null;

  Future<void> request(WindowIntent intent) {
    if (_disposed) return Future<void>.value();
    final pending = _pending;
    if (pending != null) {
      _desired = intent == _entered ? null : intent;
      return pending;
    }
    final done = Completer<void>();
    _pending = done.future;
    _desired = intent;
    _failed = null;
    scheduleMicrotask(() => _run(done));
    _publish();
    return done.future;
  }

  Future<void> _run(Completer<void> done) async {
    WindowIntent? failure;
    while (!_disposed && _desired != null) {
      final intent = _desired!;
      _entered = intent;
      _desired = null;
      failure = null;
      try {
        if (intent == WindowIntent.show) {
          await _show();
          if (!_disposed) {
            await _focus();
          }
        } else {
          await _hide();
        }
      } catch (_) {
        failure = intent;
      }
    }
    _entered = null;
    _pending = null;
    if (!_disposed) {
      _failed = failure;
      _publish();
    }
    done.complete();
  }

  void _publish() {
    _notifyDepth++;
    try {
      notifyListeners();
    } finally {
      _notifyDepth--;
      if (_disposed && _notifyDepth == 0 && !_notifierDisposed) {
        _notifierDisposed = true;
        super.dispose();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _desired = null;
    if (_notifyDepth == 0 && !_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
