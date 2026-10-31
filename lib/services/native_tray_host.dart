import 'dart:async';

import 'package:tray_manager/tray_manager.dart';

/// Immutable menu specification independent of native handles.
class TrayMenuEntry {
  const TrayMenuEntry(this.key, this.label) : isSeparator = false;
  const TrayMenuEntry.separator() : key = null, label = '', isSeparator = true;

  final String? key;
  final String label;
  final bool isSeparator;
}

/// Owns all native tray handles. Never shares a disposed menu with the host.
class NativeTrayHost {
  NativeTrayHost._();
  static final NativeTrayHost instance = NativeTrayHost._();

  TrayIcon? _icon;
  Image? _image;
  Menu? _menu;
  final _items = <MenuItem>[];
  final _listeners = <(MenuItem, ListenerId)>[];
  ListenerId? _iconListener;
  void Function(String key)? onMenuAction;
  void Function()? onIconClick;

  TrayIcon _ensureIcon() {
    final existing = _icon;
    if (existing != null) return existing;
    final icon = TrayIcon.create();
    if (icon == null) throw StateError('Cannot create native tray icon');
    _iconListener = icon.addListener((event) {
      if (event is TrayIconClickedEvent) onIconClick?.call();
      if (event is TrayIconRightClickedEvent) icon.openContextMenu();
    });
    _icon = icon;
    return icon;
  }

  Future<void> publishIcon() async {
    final image = ImageAsset.fromAsset('assets/tray_icon.png');
    if (image == null) throw StateError('Cannot load tray icon asset');
    final icon = _ensureIcon();
    icon.icon = image;
    icon.setVisible(true);
    _image?.dispose();
    _image = image;
  }

  Future<void> publishTitle(String title) async {
    _ensureIcon().setTitle(title);
  }

  Future<void> publishMenu(List<TrayMenuEntry> entries) async {
    final menu = Menu.create();
    if (menu == null) throw StateError('Cannot create native tray menu');
    final items = <MenuItem>[];
    final listeners = <(MenuItem, ListenerId)>[];
    try {
      for (final entry in entries) {
        if (entry.isSeparator) {
          menu.addSeparator();
          continue;
        }
        final item = MenuItem.createWithLabelAndType(
          entry.label,
          MenuItemType.normal,
        );
        if (item == null) throw StateError('Cannot create native tray item');
        items.add(item);
        final key = entry.key!;
        final listener = item.addListener((event) {
          if (event is MenuItemClickedEvent) onMenuAction?.call(key);
        });
        listeners.add((item, listener));
        menu.addItem(item);
      }
      _ensureIcon().setContextMenu(menu);
    } catch (_) {
      for (final (item, listener) in listeners) {
        item.removeListener(listener);
      }
      for (final item in items) {
        item.dispose();
      }
      menu.dispose();
      rethrow;
    }
    final previousMenu = _menu;
    final previousItems = List<MenuItem>.of(_items);
    final previousListeners = List<(MenuItem, ListenerId)>.of(_listeners);
    _menu = menu;
    _items
      ..clear()
      ..addAll(items);
    _listeners
      ..clear()
      ..addAll(listeners);
    // Defer disposal: menu callbacks may replace their own menu.
    Timer.run(() {
      for (final (item, listener) in previousListeners) {
        item.removeListener(listener);
      }
      for (final item in previousItems) {
        item.dispose();
      }
      previousMenu?.dispose();
    });
  }

  void dispose() {
    onMenuAction = null;
    onIconClick = null;
    final icon = _icon;
    if (icon != null && _iconListener != null) {
      icon.removeListener(_iconListener!);
    }
    _iconListener = null;
    _icon = null;
    _menu?.dispose();
    _menu = null;
    for (final (item, listener) in _listeners) {
      item.removeListener(listener);
    }
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    _listeners.clear();
    _image?.dispose();
    _image = null;
    icon?.dispose();
  }
}
