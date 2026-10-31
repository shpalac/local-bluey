import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/native_tray_host.dart';
import 'package:local_bluey/services/tray_publication_caller.dart';

class _FakeHandle implements TrayNativeHandle {
  bool disposed = false;
  @override
  void dispose() => disposed = true;
}

class _FakeImage extends _FakeHandle implements TrayNativeImage {}

class _FakeItem extends _FakeHandle implements TrayNativeMenuItem {
  void Function()? click;
  final subscription = _FakeHandle();
  @override
  TrayNativeHandle listen(void Function() callback) {
    click = callback;
    return subscription;
  }

  void invoke() {
    if (!subscription.disposed) click?.call();
  }
}

class _FakeMenu extends _FakeHandle implements TrayNativeMenu {
  final items = <_FakeItem>[];
  int separators = 0;
  @override
  void addSeparator() => separators++;
  @override
  void addItem(TrayNativeMenuItem item) => items.add(item as _FakeItem);
}

class _FakeIcon extends _FakeHandle implements TrayNativeIcon {
  void Function()? click;
  void Function()? rightClick;
  final subscription = _FakeHandle();
  TrayNativeImage? image;
  TrayNativeMenu? menu;
  String? title;
  int opened = 0;
  @override
  TrayNativeHandle listen(
    void Function() onClick,
    void Function() onRightClick,
  ) {
    click = onClick;
    rightClick = onRightClick;
    return subscription;
  }

  @override
  void show(TrayNativeImage value) => image = value;
  @override
  void setTitle(String value) => title = value;
  @override
  void setContextMenu(TrayNativeMenu value) => menu = value;
  @override
  void openContextMenu() => opened++;
}

class _FakeBackend implements TrayNativeBackend {
  final icons = <_FakeIcon>[];
  final images = <_FakeImage>[];
  final menus = <_FakeMenu>[];
  final items = <_FakeItem>[];
  final assets = <String>[];
  bool failAsset = false;
  bool failItem = false;
  @override
  TrayNativeImage loadImage(String assetPath) {
    assets.add(assetPath);
    if (failAsset) throw StateError('asset unavailable');
    final image = _FakeImage();
    images.add(image);
    return image;
  }

  @override
  TrayNativeIcon createIcon() {
    final icon = _FakeIcon();
    icons.add(icon);
    return icon;
  }

  @override
  TrayNativeMenu createMenu() {
    final menu = _FakeMenu();
    menus.add(menu);
    return menu;
  }

  @override
  TrayNativeMenuItem createItem(String label) {
    if (failItem) throw StateError('item unavailable');
    final item = _FakeItem();
    items.add(item);
    return item;
  }
}

void main() {
  test('native tray menu accepts all real inactive and active actions', () {
    for (final active in [false, true]) {
      final entries = TrayPublicationCaller.menuFor(active);
      expect(() => validateTrayMenuEntries(entries), returnsNormally);
      expect(
        entries
            .where((entry) => !entry.isSeparator)
            .map((entry) => entry.key)
            .toSet()
            .length,
        entries.where((entry) => !entry.isSeparator).length,
      );
    }
  });

  test(
    'native tray menu rejects duplicate actions before native allocation',
    () {
      expect(
        () => validateTrayMenuEntries([
          const TrayMenuEntry('quit', 'Quit'),
          const TrayMenuEntry('quit', 'Quit again'),
        ]),
        throwsArgumentError,
      );
    },
  );

  test('native tray menu rejects missing action keys and labels', () {
    expect(
      () => validateTrayMenuEntries([const TrayMenuEntry('', 'Missing key')]),
      throwsArgumentError,
    );
    expect(
      () => validateTrayMenuEntries([const TrayMenuEntry('quit', '')]),
      throwsArgumentError,
    );
  });

  test('native tray separators cannot dispatch a menu action', () {
    final entries = TrayPublicationCaller.menuFor(true);
    expect(
      entries
          .where((entry) => entry.isSeparator)
          .every((entry) => entry.key == null && entry.label.isEmpty),
      isTrue,
    );
    expect(() => validateTrayMenuEntries(entries), returnsNormally);
  });
  test(
    'native host allocates one icon and dispatches clicks and menu IDs',
    () async {
      final backend = _FakeBackend();
      final host = NativeTrayHost.testing(backend);
      addTearDown(host.dispose);
      final actions = <String>[];
      var iconClicks = 0;
      host.onIconClick = () => iconClicks++;
      host.onMenuAction = actions.add;
      await host.publishIcon();
      await host.publishTitle('● 05:00');
      await host.publishMenu([
        const TrayMenuEntry('stopwatch', 'Stop watching'),
        const TrayMenuEntry.separator(),
        const TrayMenuEntry('quit', 'Quit'),
      ]);
      expect(backend.assets, ['assets/tray_icon.png']);
      expect(backend.icons.length, 1);
      expect(backend.icons.single.title, '● 05:00');
      expect(backend.menus.single.separators, 1);
      backend.icons.single.click?.call();
      backend.icons.single.rightClick?.call();
      backend.items.first.invoke();
      backend.items.last.invoke();
      expect(iconClicks, 1);
      expect(backend.icons.single.opened, 1);
      expect(actions, ['stopwatch', 'quit']);
      host.dispose();
      expect(backend.icons.single.disposed, isTrue);
      expect(backend.icons.single.subscription.disposed, isTrue);
      expect(backend.images.single.disposed, isTrue);
      expect(backend.menus.single.disposed, isTrue);
      expect(backend.items.every((item) => item.disposed), isTrue);
      expect(backend.items.every((item) => item.subscription.disposed), isTrue);
    },
  );

  test('native host defers old menu cleanup until callbacks return', () async {
    final backend = _FakeBackend();
    final host = NativeTrayHost.testing(backend);
    addTearDown(host.dispose);
    await host.publishMenu([const TrayMenuEntry('first', 'First')]);
    final oldMenu = backend.menus.first;
    final oldItem = backend.items.first;
    var oldDisposedInsideCallback = false;
    final replaced = Completer<void>();
    host.onMenuAction = (key) {
      if (key != 'first') return;
      host.publishMenu([const TrayMenuEntry('second', 'Second')]).then((_) {
        oldDisposedInsideCallback = oldMenu.disposed;
        replaced.complete();
      });
    };
    oldItem.invoke();
    await replaced.future;
    expect(oldDisposedInsideCallback, isFalse);
    expect(oldMenu.disposed, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(oldMenu.disposed, isTrue);
    expect(oldItem.disposed, isTrue);
    expect(oldItem.subscription.disposed, isTrue);
    backend.items.last.invoke();
    host.dispose();
  });

  test(
    'native host rejects allocation failures and releases partial menu',
    () async {
      final backend = _FakeBackend()..failItem = true;
      final host = NativeTrayHost.testing(backend);
      addTearDown(host.dispose);
      await expectLater(
        host.publishMenu([const TrayMenuEntry('show', 'Show')]),
        throwsStateError,
      );
      expect(backend.menus.single.disposed, isTrue);
      expect(backend.icons, isEmpty);
      backend.failItem = false;
      await host.publishMenu([const TrayMenuEntry('show', 'Show')]);
      expect(backend.icons.length, 1);
      host.dispose();
    },
  );

  test('native host dispose disables callbacks and is idempotent', () async {
    final backend = _FakeBackend();
    final host = NativeTrayHost.testing(backend);
    addTearDown(host.dispose);
    var callbacks = 0;
    host.onIconClick = () => callbacks++;
    host.onMenuAction = (_) => callbacks++;
    await host.publishIcon();
    await host.publishMenu([const TrayMenuEntry('stop', 'Stop')]);
    final icon = backend.icons.single;
    final item = backend.items.single;
    host.dispose();
    host.dispose();
    icon.click?.call();
    item.invoke();
    expect(callbacks, 0);
    expect(icon.subscription.disposed, isTrue);
    expect(item.subscription.disposed, isTrue);
  });
}
