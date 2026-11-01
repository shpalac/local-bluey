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

/// Reject malformed native-menu definitions before allocating OS handles.
void validateTrayMenuEntries(List<TrayMenuEntry> entries) {
  final keys = <String>{};
  for (final entry in entries) {
    if (entry.isSeparator) {
      if (entry.key != null || entry.label.isNotEmpty) {
        throw ArgumentError('Separators cannot have actions or labels');
      }
      continue;
    }
    final key = entry.key;
    if (key == null || key.isEmpty || entry.label.isEmpty) {
      throw ArgumentError('Native tray actions require a key and label');
    }
    if (!keys.add(key)) {
      throw ArgumentError.value(key, 'key', 'Duplicate native tray action');
    }
  }
}

/// Injectable bridge around native handles; the production implementation below
/// preserves the plugin API, while tests observe real host ownership behavior.
abstract class TrayNativeHandle {
  void dispose();
}

abstract class TrayNativeImage implements TrayNativeHandle {}

abstract class TrayNativeMenuItem implements TrayNativeHandle {
  TrayNativeHandle listen(void Function() onClick);
}

abstract class TrayNativeMenu implements TrayNativeHandle {
  void addSeparator();
  void addItem(TrayNativeMenuItem item);
}

abstract class TrayNativeIcon implements TrayNativeHandle {
  TrayNativeHandle listen(
    void Function() onClick,
    void Function() onRightClick,
  );
  void show(TrayNativeImage image);
  void setTitle(String title);
  void setContextMenu(TrayNativeMenu menu);
  void openContextMenu();
}

abstract class TrayNativeBackend {
  TrayNativeImage loadImage(String assetPath);
  TrayNativeIcon createIcon();
  TrayNativeMenu createMenu();
  TrayNativeMenuItem createItem(String label);
}

class _DisposableListener implements TrayNativeHandle {
  _DisposableListener(this._remove);
  final void Function() _remove;
  @override
  void dispose() => _remove();
}

class _PluginImage implements TrayNativeImage {
  _PluginImage(this.image);
  final Image image;
  @override
  void dispose() => image.dispose();
}

class _PluginMenuItem implements TrayNativeMenuItem {
  _PluginMenuItem(this.item);
  final MenuItem item;
  @override
  TrayNativeHandle listen(void Function() onClick) {
    final id = item.addListener((event) {
      if (event is MenuItemClickedEvent) onClick();
    });
    return _DisposableListener(() => item.removeListener(id));
  }

  @override
  void dispose() => item.dispose();
}

class _PluginMenu implements TrayNativeMenu {
  _PluginMenu(this.menu);
  final Menu menu;
  @override
  void addSeparator() => menu.addSeparator();
  @override
  void addItem(TrayNativeMenuItem item) =>
      menu.addItem((item as _PluginMenuItem).item);
  @override
  void dispose() => menu.dispose();
}

class _PluginIcon implements TrayNativeIcon {
  _PluginIcon(this.icon);
  final TrayIcon icon;
  @override
  TrayNativeHandle listen(
    void Function() onClick,
    void Function() onRightClick,
  ) {
    final id = icon.addListener((event) {
      if (event is TrayIconClickedEvent) onClick();
      if (event is TrayIconRightClickedEvent) onRightClick();
    });
    return _DisposableListener(() => icon.removeListener(id));
  }

  @override
  void show(TrayNativeImage image) {
    icon.icon = (image as _PluginImage).image;
    icon.setVisible(true);
  }

  @override
  void setTitle(String title) => icon.setTitle(title);
  @override
  void setContextMenu(TrayNativeMenu menu) =>
      icon.setContextMenu((menu as _PluginMenu).menu);
  @override
  void openContextMenu() => icon.openContextMenu();
  @override
  void dispose() => icon.dispose();
}

class _PluginBackend implements TrayNativeBackend {
  const _PluginBackend();
  @override
  TrayNativeImage loadImage(String assetPath) {
    final image = ImageAsset.fromAsset(assetPath);
    if (image == null) throw StateError('Cannot load tray icon asset');
    return _PluginImage(image);
  }

  @override
  TrayNativeIcon createIcon() {
    final icon = TrayIcon.create();
    if (icon == null) throw StateError('Cannot create native tray icon');
    return _PluginIcon(icon);
  }

  @override
  TrayNativeMenu createMenu() {
    final menu = Menu.create();
    if (menu == null) throw StateError('Cannot create native tray menu');
    return _PluginMenu(menu);
  }

  @override
  TrayNativeMenuItem createItem(String label) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) throw StateError('Cannot create native tray item');
    return _PluginMenuItem(item);
  }
}

/// Owns all native tray handles. Never shares a disposed menu with the host.
class NativeTrayHost {
  NativeTrayHost._() : _backend = const _PluginBackend();
  NativeTrayHost.testing(this._backend);
  static final NativeTrayHost instance = NativeTrayHost._();

  final TrayNativeBackend _backend;
  TrayNativeIcon? _icon;
  TrayNativeImage? _image;
  TrayNativeMenu? _menu;
  final _items = <TrayNativeMenuItem>[];
  final _listeners = <TrayNativeHandle>[];
  TrayNativeHandle? _iconListener;
  void Function(String key)? onMenuAction;
  void Function()? onIconClick;

  TrayNativeIcon _ensureIcon() {
    final existing = _icon;
    if (existing != null) return existing;
    final icon = _backend.createIcon();
    _iconListener = icon.listen(
      () => onIconClick?.call(),
      () => icon.openContextMenu(),
    );
    _icon = icon;
    return icon;
  }

  Future<void> publishIcon() async {
    final image = _backend.loadImage('assets/tray_icon.png');
    try {
      _ensureIcon().show(image);
    } catch (_) {
      image.dispose();
      rethrow;
    }
    _image?.dispose();
    _image = image;
  }

  Future<void> publishTitle(String title) async {
    _ensureIcon().setTitle(title);
  }

  Future<void> publishMenu(List<TrayMenuEntry> entries) async {
    validateTrayMenuEntries(entries);
    final menu = _backend.createMenu();
    final items = <TrayNativeMenuItem>[];
    final listeners = <TrayNativeHandle>[];
    try {
      for (final entry in entries) {
        if (entry.isSeparator) {
          menu.addSeparator();
          continue;
        }
        final item = _backend.createItem(entry.label);
        items.add(item);
        final key = entry.key!;
        listeners.add(item.listen(() => onMenuAction?.call(key)));
        menu.addItem(item);
      }
      _ensureIcon().setContextMenu(menu);
    } catch (_) {
      for (final listener in listeners) {
        listener.dispose();
      }
      for (final item in items) {
        item.dispose();
      }
      menu.dispose();
      rethrow;
    }
    final previousMenu = _menu;
    final previousItems = List<TrayNativeMenuItem>.of(_items);
    final previousListeners = List<TrayNativeHandle>.of(_listeners);
    _menu = menu;
    _items
      ..clear()
      ..addAll(items);
    _listeners
      ..clear()
      ..addAll(listeners);
    // The callback may replace the menu synchronously. Retire old handles
    // only after that callback returns to the event loop.
    Timer.run(() {
      for (final listener in previousListeners) {
        listener.dispose();
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
    _iconListener?.dispose();
    _iconListener = null;
    final icon = _icon;
    _icon = null;
    _menu?.dispose();
    _menu = null;
    for (final listener in _listeners) {
      listener.dispose();
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
