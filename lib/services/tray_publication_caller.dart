import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'screen_watch.dart';

/// Desired local publication, not observed native tray state.
class TrayPublicationState {
  const TrayPublicationState({required this.active, required this.title});
  factory TrayPublicationState.watch(ScreenWatch watch) {
    final active = watch.isActive;
    final r = watch.remaining;
    final mm = r.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = r.inSeconds.remainder(60).toString().padLeft(2, '0');
    return TrayPublicationState(
      active: active,
      title: active ? '● $mm:$ss' : '',
    );
  }
  final bool active;
  final String title;
}

/// MacHome's publication lifetime only. Never destroys the shared plugin.
class TrayPublicationCaller extends ChangeNotifier {
  TrayPublicationCaller({TrayPublicationState Function()? read})
    : this.operations(
        read: read ?? () => TrayPublicationState.watch(ScreenWatch.instance),
        icon: () => trayManager.setIcon('assets/tray_icon.png'),
        title: trayManager.setTitle,
        menu: (active) => trayManager.setContextMenu(menuFor(active)),
      );
  TrayPublicationCaller.operations({
    required TrayPublicationState Function() read,
    required Future<void> Function() icon,
    required Future<void> Function(String) title,
    required Future<void> Function(bool) menu,
  }) : this._operations(read, icon, title, menu);
  TrayPublicationCaller._operations(
    this._read,
    this._icon,
    this._title,
    this._menu,
  );
  final TrayPublicationState Function() _read;
  final Future<void> Function() _icon;
  final Future<void> Function(String) _title;
  final Future<void> Function(bool) _menu;
  Future<void>? _pending;
  bool _disposed = false, _notifierDisposed = false, _again = false;
  int _notifyDepth = 0;
  bool _failed = false;
  bool? _failedActive;
  bool _iconPublished = false,
      _titleUncompleted = false,
      _menuUncompleted = false;
  String? _publishedTitle;
  bool? _publishedActive;
  TrayPublicationState? _desired;
  bool get loading => _pending != null;
  bool get failed => _failed;
  bool get visible => loading || failed;
  bool get iconPublished => _iconPublished;
  String? get publishedTitle => _publishedTitle;
  bool? get publishedActive => _publishedActive;
  TrayPublicationState? get desired => _desired;

  static Menu menuFor(bool active) => Menu(
    items: [
      MenuItem(key: 'show', label: 'Show Bluey'),
      MenuItem(key: 'hide', label: 'Hide'),
      MenuItem.separator(),
      MenuItem(key: 'ask', label: 'Ask Bluey (wake)'),
      MenuItem(key: 'mute', label: 'Mute replies'),
      MenuItem(key: 'status', label: 'Status'),
      MenuItem.separator(),
      if (active)
        MenuItem(key: 'stopwatch', label: 'Stop watching (kill switch)'),
      MenuItem(key: 'stop', label: 'Stop Bluey (kill switch)'),
      MenuItem(key: 'resume', label: 'Resume Bluey'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ],
  );

  Future<void> request({bool explicitRetry = false}) {
    if (_disposed) return Future<void>.value();
    final pending = _pending;
    if (pending != null) {
      _again = true;
      return pending;
    }
    // Failed publication is not retried by countdown ticks. A new actual
    // active-state transition or explicit retry may attempt fresh state.
    if (_failed && !explicitRetry) {
      try {
        _desired = _read();
        if (_desired!.active == _failedActive) return Future<void>.value();
      } catch (_) {
        return Future<void>.value();
      }
    }
    final done = Completer<void>();
    _pending = done.future;
    scheduleMicrotask(() => _run(done));
    _publish();
    return done.future;
  }

  TrayPublicationState _sample() => _desired = _read();

  Future<void> _run(Completer<void> done) async {
    var passes = 0;
    while (!_disposed && passes++ < 2) {
      _again = false;
      TrayPublicationState? entered;
      var failedPass = false;
      try {
        entered = _sample();
        if (!_iconPublished) {
          await _icon();
          if (_disposed) break;
          _iconPublished = true;
        }
        entered = _sample();
        if (_titleUncompleted || entered.title != _publishedTitle) {
          _titleUncompleted = true;
          await _title(entered.title);
          if (_disposed) break;
          _publishedTitle = entered.title;
          _titleUncompleted = false;
        }
        entered = _sample();
        if (_menuUncompleted || entered.active != _publishedActive) {
          _menuUncompleted = true;
          await _menu(entered.active);
          if (_disposed) break;
          _publishedActive = entered.active;
          _menuUncompleted = false;
        }
        final latest = _sample();
        // Re-sampling itself does not enqueue work. Only a real notification
        // during the pass may request one bounded latest-state successor.
        _failed = false;
        _failedActive = null;
        if (!_again ||
            (latest.title == _publishedTitle &&
                latest.active == _publishedActive)) {
          break;
        }
      } catch (_) {
        failedPass = true;
        if (!_disposed) {
          _failed = true;
          _failedActive = entered?.active ?? _desired?.active;
        }
      }
      if (_disposed) break;
      if (failedPass) {
        try {
          final latest = _sample();
          if (!_again || latest.active == _failedActive) break;
        } catch (_) {
          break;
        }
      }
    }
    _pending = null;
    if (!_disposed) _publish();
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
    _again = false;
    if (_notifyDepth == 0 && !_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
