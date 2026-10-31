import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/mac_home_tray_wiring.dart';
import 'package:local_bluey/services/native_tray_host.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/tray_publication_caller.dart';

class _TrackedHandle implements TrayNativeHandle {
  int disposeCalls = 0;

  @override
  void dispose() => disposeCalls++;
}

class _TrackedImage extends _TrackedHandle implements TrayNativeImage {}

class _TrackedItem extends _TrackedHandle implements TrayNativeMenuItem {
  _TrackedItem(this.backend);

  final _TrackedBackend backend;

  @override
  TrayNativeHandle listen(void Function() onClick) =>
      backend.track(_TrackedHandle());
}

class _TrackedMenu extends _TrackedHandle implements TrayNativeMenu {
  @override
  void addItem(TrayNativeMenuItem item) {}

  @override
  void addSeparator() {}
}

class _TrackedIcon extends _TrackedHandle implements TrayNativeIcon {
  _TrackedIcon(this.backend);

  final _TrackedBackend backend;

  @override
  TrayNativeHandle listen(
    void Function() onClick,
    void Function() onRightClick,
  ) => backend.track(_TrackedHandle());

  @override
  void openContextMenu() {}

  @override
  void setContextMenu(TrayNativeMenu menu) {}

  @override
  void setTitle(String title) {}

  @override
  void show(TrayNativeImage image) {}
}

class _TrackedBackend implements TrayNativeBackend {
  final handles = <_TrackedHandle>[];

  T track<T extends _TrackedHandle>(T handle) {
    handles.add(handle);
    return handle;
  }

  @override
  TrayNativeImage loadImage(String assetPath) => track(_TrackedImage());

  @override
  TrayNativeIcon createIcon() => track(_TrackedIcon(this));

  @override
  TrayNativeMenu createMenu() => track(_TrackedMenu());

  @override
  TrayNativeMenuItem createItem(String label) => track(_TrackedItem(this));
}

void main() {
  test(
    'MacHome disposal releases every allocated native tray handle once',
    () async {
      final backend = _TrackedBackend();
      final host = NativeTrayHost.testing(backend);
      final watch = ScreenWatch.forTesting();
      final publication = TrayPublicationCaller.operations(
        read: () => const TrayPublicationState(active: false, title: ''),
        icon: host.publishIcon,
        title: host.publishTitle,
        menu: (active) =>
            host.publishMenu(TrayPublicationCaller.menuFor(active)),
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
      expect(backend.handles, isNotEmpty);
      expect(backend.handles.every((handle) => handle.disposeCalls == 0), true);

      wiring.dispose();
      wiring.dispose();
      expect(
        backend.handles.every((handle) => handle.disposeCalls == 1),
        true,
        reason: 'Every allocated icon, image, menu, item and listener is released once.',
      );

      final allocatedBeforeNotification = backend.handles.length;
      watch.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(backend.handles, hasLength(allocatedBeforeNotification));
      expect(backend.handles.every((handle) => handle.disposeCalls == 1), true);
      watch.dispose();
    },
  );
}
