import 'dart:async';

import 'native_tray_host.dart';
import 'screen_watch.dart';
import 'tray_publication_caller.dart';

/// Owns MacHome's single native tray publication and listener lifetime.
class MacHomeTrayWiring {
  MacHomeTrayWiring({
    required this.publication,
    required this.host,
    required this.watch,
    required this.mounted,
    required this.killed,
    required this.onIconClick,
    required this.onMenuAction,
  });

  final TrayPublicationCaller publication;
  final NativeTrayHost host;
  final ScreenWatch watch;
  final bool Function() mounted;
  final bool Function() killed;
  final void Function() onIconClick;
  final void Function(String key) onMenuAction;

  bool _attached = false;
  bool _disposed = false;

  void attach() {
    if (_disposed) throw StateError('Tray wiring is disposed');
    if (_attached) return;
    _attached = true;
    host
      ..onIconClick = _handleIconClick
      ..onMenuAction = _handleMenuAction;
    watch.addListener(_onWatchChanged);
    if (mounted() && !killed()) unawaited(publication.request());
  }

  void _handleIconClick() {
    if (_disposed || !mounted() || killed()) return;
    onIconClick();
  }

  void _handleMenuAction(String key) {
    if (_disposed || !mounted()) return;
    // Menu actions remain dispatchable while killed so Resume and Quit work.
    onMenuAction(key);
  }

  void _onWatchChanged() {
    if (_disposed || !mounted() || killed()) return;
    unawaited(publication.request());
  }

  /// Re-publishes after a safety-state transition such as Resume.
  void onSafetyChanged() {
    if (_disposed || !_attached || !mounted() || killed()) return;
    unawaited(publication.request());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_attached) watch.removeListener(_onWatchChanged);
    publication.dispose();
    host
      ..onIconClick = null
      ..onMenuAction = null
      ..dispose();
  }
}
