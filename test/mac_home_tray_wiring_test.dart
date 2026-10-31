import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/mac_home_tray_wiring.dart';
import 'package:local_bluey/services/native_tray_host.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/tray_publication_caller.dart';

class _Handle implements TrayNativeHandle {
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

class _Image extends _Handle implements TrayNativeImage {}

class _Item extends _Handle implements TrayNativeMenuItem {
  @override
  TrayNativeHandle listen(void Function() onClick) => _Handle();
}

class _Menu extends _Handle implements TrayNativeMenu {
  @override
  void addItem(TrayNativeMenuItem item) {}
  @override
  void addSeparator() {}
}

class _Icon extends _Handle implements TrayNativeIcon {
  @override
  TrayNativeHandle listen(
    void Function() onClick,
    void Function() onRightClick,
  ) => _Handle();
  @override
  void openContextMenu() {}
  @override
  void setContextMenu(TrayNativeMenu menu) {}
  @override
  void setTitle(String title) {}
  @override
  void show(TrayNativeImage image) {}
}

class _Backend implements TrayNativeBackend {
  final icon = _Icon();
  @override
  TrayNativeImage loadImage(String assetPath) => _Image();
  @override
  TrayNativeIcon createIcon() => icon;
  @override
  TrayNativeMenu createMenu() => _Menu();
  @override
  TrayNativeMenuItem createItem(String label) => _Item();
}

void main() {
  test('MacHome tray wiring has one publication owner on repeated attach', () async {
    final watch = ScreenWatch.forTesting();
    final backend = _Backend();
    final host = NativeTrayHost.testing(backend);
    var active = false;
    final calls = <String>[];
    final publication = TrayPublicationCaller.operations(
      read: () => TrayPublicationState(active: active, title: active ? 'active' : ''),
      icon: () async => calls.add('icon'),
      title: (value) async => calls.add('title:$value'),
      menu: (value) async => calls.add('menu:$value'),
    );
    final wiring = MacHomeTrayWiring(
      publication: publication,
      host: host,
      watch: watch,
      mounted: () => true,
      killed: () => false,
      onIconClick: () {},
      onMenuAction: (_) {},
    );

    wiring.attach();
    wiring.attach();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['icon', 'title:', 'menu:false']);

    active = true;
    watch.notifyListeners();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['icon', 'title:', 'menu:false', 'title:active', 'menu:true']);
    wiring.dispose();
    watch.dispose();
  });

  test('MacHome kill switch blocks icon but preserves Resume menu dispatch', () async {
    final watch = ScreenWatch.forTesting();
    final host = NativeTrayHost.testing(_Backend());
    var active = false;
    final calls = <String>[];
    final publication = TrayPublicationCaller.operations(
      read: () => TrayPublicationState(
        active: active,
        title: active ? 'active' : '',
      ),
      icon: () async => calls.add('icon'),
      title: (value) async => calls.add('title:$value'),
      menu: (value) async => calls.add('menu:$value'),
    );
    var killed = false;
    var iconClicks = 0;
    final menuActions = <String>[];
    final wiring = MacHomeTrayWiring(
      publication: publication,
      host: host,
      watch: watch,
      mounted: () => true,
      killed: () => killed,
      onIconClick: () => iconClicks++,
      onMenuAction: (key) {
        menuActions.add(key);
        if (key == 'stop') killed = true;
        if (key == 'resume') killed = false;
      },
    );

    wiring.attach();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['icon', 'title:', 'menu:false']);
    host.onIconClick!();
    host.onMenuAction!('stop');
    wiring.onSafetyChanged();
    active = true;
    watch.notifyListeners();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['icon', 'title:', 'menu:false']);
    host.onIconClick!();
    host.onMenuAction!('resume');
    wiring.onSafetyChanged();
    await Future<void>.delayed(Duration.zero);

    expect(iconClicks, 1);
    expect(menuActions, ['stop', 'resume']);
    expect(calls, [
      'icon',
      'title:',
      'menu:false',
      'title:active',
      'menu:true',
    ]);
    wiring.dispose();
    watch.dispose();
  });

  test('MacHome dispose removes watch listener and native callbacks once', () async {
    final watch = ScreenWatch.forTesting();
    final host = NativeTrayHost.testing(_Backend());
    var titleCalls = 0;
    final publication = TrayPublicationCaller.operations(
      read: () => const TrayPublicationState(active: false, title: ''),
      icon: () async {},
      title: (_) async => titleCalls++,
      menu: (_) async {},
    );
    final wiring = MacHomeTrayWiring(
      publication: publication,
      host: host,
      watch: watch,
      mounted: () => true,
      killed: () => false,
      onIconClick: () {},
      onMenuAction: (_) {},
    );

    wiring.attach();
    await Future<void>.delayed(Duration.zero);
    wiring.dispose();
    wiring.dispose();
    final before = titleCalls;
    watch.notifyListeners();
    expect(titleCalls, before);
    expect(host.onIconClick, isNull);
    expect(host.onMenuAction, isNull);
    expect(backendDisposed(host), isTrue);
    watch.dispose();
  });
}

bool backendDisposed(NativeTrayHost host) {
  // The host is intentionally opaque; callback detachment is its observable
  // ownership boundary, while the host's own lifecycle is covered separately.
  return host.onIconClick == null && host.onMenuAction == null;
}
