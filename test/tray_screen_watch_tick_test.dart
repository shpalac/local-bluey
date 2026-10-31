import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/tray_publication_caller.dart';

void main() {
  test('watch clock ticks publish title without repeating native menu', () {
    fakeAsync((time) {
      final startedAt = DateTime.utc(2026, 10, 31, 12);
      final watch = ScreenWatch.forTesting(
        clock: Clock(() => startedAt.add(time.elapsed)),
        localOnly: () async => true,
        allowlist: () async => ['com.example.editor'],
        denylist: () async => [],
      );
      final titles = <String>[];
      final menus = <bool>[];
      var icons = 0;
      final caller = TrayPublicationCaller.operations(
        read: () => TrayPublicationState.watch(watch),
        icon: () async => icons++,
        title: (title) async => titles.add(title),
        menu: (active) async => menus.add(active),
      );
      watch.addListener(() {
        caller.request();
      });

      String? startResult;
      watch
          .start(length: const Duration(seconds: 3), consentConfirmed: true)
          .then((value) => startResult = value);
      time.flushMicrotasks();
      expect(startResult, isNull);
      expect(watch.isActive, isTrue);
      time.flushMicrotasks();
      expect(titles.last, '● 00:03');
      expect(menus, [true]);

      time.elapse(const Duration(seconds: 1));
      time.flushMicrotasks();
      expect(titles.last, '● 00:02');
      expect(menus, [true]);
      expect(icons, 1);

      time.elapse(const Duration(seconds: 2));
      time.flushMicrotasks();
      expect(watch.isActive, isFalse);
      expect(titles.last, '');
      expect(menus, [true, false]);
      expect(icons, 1);
      caller.dispose();
      watch.dispose();
    });
  });
}
