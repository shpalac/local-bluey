import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/linux_portal_host_control.dart';

class FakeRunner {
  final calls = <(String, List<String>)>[];
  final Map<String, String> stdoutByKey;
  final Set<String> binaries;

  FakeRunner({Map<String, String>? stdout, Set<String>? binaries})
    : stdoutByKey = stdout ?? {},
      binaries =
          binaries ??
          {'gdbus', 'convert', 'tesseract', 'xdg-open', 'gtk-launch'};

  Future<ProcessResult> call(String exe, List<String> args) async {
    calls.add((exe, args));
    final key = '$exe ${args.join(' ')}';
    for (final entry in stdoutByKey.entries) {
      if (key.startsWith(entry.key)) {
        return ProcessResult(0, 0, entry.value, '');
      }
    }
    return ProcessResult(0, 0, '', '');
  }

  Future<bool> has(String exe) async => binaries.contains(exe);
}

LinuxPortalHostControl hostFor(
  FakeRunner runner, {
  Map<String, String> env = const {'XDG_SESSION_TYPE': 'wayland'},
}) {
  return LinuxPortalHostControl(
    run: runner.call,
    env: (k) => env[k],
    hasBinary: runner.has,
  );
}

void main() {
  test('trust requires only gdbus; input stays opt-in', () async {
    final runner = FakeRunner();
    expect(await hostFor(runner).isTrusted(), isTrue);
    expect(await hostFor(runner).hasInput, isFalse);

    final noGdbus = FakeRunner(binaries: {'convert'});
    expect(await hostFor(noGdbus).isTrusted(), isFalse);
  });

  test('input without ydotool explains the uinput setup', () async {
    final host = hostFor(FakeRunner());
    expect(
      () => host.type('hi'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('ydotool'), contains('udev'), contains('/dev/uinput')),
        ),
      ),
    );
  });

  test(
    'snapshot parses the portal Response and returns image + size',
    () async {
      final runner = FakeRunner(
        stdout: {
          'gdbus call': "(objectpath '/org/freedesktop/portal/desktop/request/1_42/bluey0',)",
          'gdbus monitor':
              'Response: (0, {\'uri\': <\'file:///tmp/shot.png\'>})',
          'convert /tmp/shot.png -format': '1920 1080',
          'tesseract': '',
        },
      );
      final host = LinuxPortalHostControl(
        run: runner.call,
        env: (k) => {'XDG_SESSION_TYPE': 'wayland'}[k],
        hasBinary: runner.has,
        readBytes: (_) async => Uint8List.fromList([9, 9]),
        makeTempDir: () async => Directory.systemTemp.createTemp('bluey-test-'),
      );
      final snap = await host.snapshot();
      expect(snap.jpeg, [9, 9]);
      expect((snap.width, snap.height), (1920.0, 1080.0));
      // capture downscales through convert
      expect(
        runner.calls.any((c) => c.$1 == 'convert' && c.$2.contains('-resize')),
        isTrue,
      );
    },
  );

  test('denied portal consent is a clean error, not a hang', () async {
    final runner = FakeRunner(
      stdout: {
        'gdbus call': "(objectpath '/org/freedesktop/portal/desktop/request/1_42/bluey0',)",
        'gdbus monitor': 'Response: (1, {})',
      },
    );
    final host = hostFor(runner);
    expect(
      () => host.snapshot(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('denied'),
        ),
      ),
    );
  });

  test('snapshotRegion is an honest unsupported, not a fake', () {
    expect(
      () => hostFor(FakeRunner()).snapshotRegion(0, 0, 100, 100),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('mouseLocation is an honest unsupported on Wayland', () {
    expect(
      () => hostFor(FakeRunner()).mouseLocation(),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('press maps combos to evdev down/up pairs', () async {
    final runner = FakeRunner(binaries: {'gdbus', 'ydotool'});
    final label = await hostFor(runner).press('cmd+shift+t');
    expect(label, 'super+shift+t');
    expect(runner.calls.last.$1, 'ydotool');
    expect(runner.calls.last.$2, [
      'key',
      '125:1',
      '42:1',
      '20:1',
      '20:0',
      '42:0',
      '125:0',
    ]);
  });

  test('unmapped keys fail loudly', () async {
    final runner = FakeRunner(binaries: {'gdbus', 'ydotool'});
    expect(
      () => hostFor(runner).press('f13'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('type passes text as one argv element through ydotool', () async {
    final runner = FakeRunner(binaries: {'gdbus', 'ydotool'});
    await hostFor(runner).type('a; rm -rf /');
    expect(runner.calls.last.$2, ['type', '--', 'a; rm -rf /']);
  });
}
