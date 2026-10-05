import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/host_control.dart';
import 'package:local_bluey/services/linux_x11_host_control.dart';

class FakeRunner {
  final calls = <(String, List<String>)>[];
  final Map<String, String> stdoutByExe;
  final Set<String> binaries;

  FakeRunner({Map<String, String>? stdout, Set<String>? binaries})
    : stdoutByExe = stdout ?? {},
      binaries =
          binaries ??
          {
            'import',
            'convert',
            'xdotool',
            'tesseract',
            'xdg-open',
            'gtk-launch',
          };

  Future<ProcessResult> call(String exe, List<String> args) async {
    calls.add((exe, args));
    return ProcessResult(0, 0, stdoutByExe[exe] ?? '', '');
  }

  Future<bool> has(String exe) async => binaries.contains(exe);
}

void main() {
  group('session detection', () {
    test('linux with an X11 display gets the X11 backend', () {
      final host = HostControl.forPlatform(
        operatingSystem: 'linux',
        environment: {'DISPLAY': ':0', 'XDG_SESSION_TYPE': 'x11'},
      );
      expect(host, isA<LinuxX11HostControl>());
    });

    test('wayland-only sessions stay unsupported with a pointer to #151', () {
      final host = HostControl.forPlatform(
        operatingSystem: 'linux',
        environment: {'XDG_SESSION_TYPE': 'wayland'},
      );
      expect(host, isA<UnsupportedHostControl>());
      expect(
        () => host.isTrusted(),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('wayland'),
          ),
        ),
      );
    });

    test('no DISPLAY is an actionable unsupported message', () {
      final host = HostControl.forPlatform(
        operatingSystem: 'linux',
        environment: const {},
      );
      expect(host, isA<UnsupportedHostControl>());
      expect(
        () => host.isTrusted(),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('DISPLAY'),
          ),
        ),
      );
    });
  });

  group('trust and helpers', () {
    test('trusted when a display and every helper is present', () async {
      final runner = FakeRunner();
      final host = LinuxX11HostControl(
        run: runner.call,
        env: (k) => k == 'DISPLAY' ? ':0' : null,
        hasBinary: runner.has,
      );
      expect(await host.isTrusted(), isTrue);
    });

    test('untrusted without a display', () async {
      final runner = FakeRunner();
      final host = LinuxX11HostControl(
        run: runner.call,
        env: (_) => null,
        hasBinary: runner.has,
      );
      expect(await host.isTrusted(), isFalse);
    });

    test('missing helpers name the packages to install', () async {
      final runner = FakeRunner(binaries: {'xdotool'});
      final host = LinuxX11HostControl(
        run: runner.call,
        env: (k) => k == 'DISPLAY' ? ':0' : null,
        hasBinary: runner.has,
      );
      expect(
        () => host.askPermission(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('apt-get install'), contains('imagemagick')),
          ),
        ),
      );
    });
  });

  group('input calls pass argv arrays, never shell strings', () {
    late FakeRunner runner;
    late LinuxX11HostControl host;

    setUp(() {
      runner = FakeRunner(stdout: {'xdotool': ''});
      host = LinuxX11HostControl(
        run: runner.call,
        env: (k) => k == 'DISPLAY' ? ':0' : null,
        hasBinary: runner.has,
      );
    });

    test('warp moves via xdotool mousemove', () async {
      await host.warp(100.4, 200.6);
      expect(runner.calls.last.$1, 'xdotool');
      expect(runner.calls.last.$2, ['mousemove', '100', '201']);
    });

    test('click warps then clicks the right button with repeats', () async {
      await host.click(10, 20, right: true, count: 2);
      expect(runner.calls.last.$1, 'xdotool');
      expect(runner.calls.last.$2, ['click', '--repeat', '2', '3']);
    });

    test('scroll down maps to X11 button 5', () async {
      await host.scroll(0, 0, dy: 3);
      expect(runner.calls.last.$1, 'xdotool');
      expect(runner.calls.last.$2, ['click', '--repeat', '3', '5']);
    });

    test('type passes the text as a single argv element', () async {
      await host.type('hello; rm -rf /');
      expect(runner.calls.last.$1, 'xdotool');
      expect(runner.calls.last.$2, [
        'type',
        '--clearmodifiers',
        '--',
        'hello; rm -rf /',
      ]);
    });

    test('press translates macOS modifier names', () async {
      final label = await host.press('cmd+shift+t');
      expect(label, 'super+shift+t');
      expect(runner.calls.last.$1, 'xdotool');
      expect(runner.calls.last.$2, [
        'key',
        '--clearmodifiers',
        'super+shift+t',
      ]);
    });

    test('openURL goes through xdg-open', () async {
      await host.openURL('https://example.com');
      expect(runner.calls.last.$1, 'xdg-open');
      expect(runner.calls.last.$2, ['https://example.com']);
    });
  });

  group('mouse location', () {
    test('parses xdotool --shell output', () async {
      final runner = FakeRunner(
        stdout: {'xdotool': 'X=512\nY=384\nSCREEN=0\nWINDOW=1\n'},
      );
      final host = LinuxX11HostControl(
        run: runner.call,
        env: (k) => k == 'DISPLAY' ? ':0' : null,
        hasBinary: runner.has,
      );
      expect(await host.mouseLocation(), const Offset(512, 384));
    });
  });

  group('targets', () {
    test('resolveTarget rejects unknown ids with guidance', () async {
      final host = LinuxX11HostControl(
        run: FakeRunner().call,
        env: (k) => k == 'DISPLAY' ? ':0' : null,
        hasBinary: FakeRunner().has,
      );
      expect(
        () => host.resolveTarget('W99'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('fresh snapshot'),
          ),
        ),
      );
    });

    test('tesseract TSV becomes target lines and resolvable ids', () async {
      const tsv =
          'level\tpage\tblock\tpar\tline\tword\tleft\ttop\twidth\theight\tconf\ttext\n'
          '5\t1\t1\t1\t1\t1\t100\t200\t40\t20\t95.5\tHello\n'
          '5\t1\t1\t1\t1\t2\t300\t400\t50\t24\t10.0\tweak\n'
          '5\t1\t1\t1\t1\t3\t500\t600\t60\t30\t88.0\tWorld\n';
      final runner = FakeRunner(stdout: {'tesseract': tsv});
      final host = LinuxX11HostControl(
        run: runner.call,
        env: (k) => k == 'DISPLAY' ? ':0' : null,
        hasBinary: runner.has,
      );
      final targets = await host.snapshotTargetsForTest('/tmp/x.png');
      expect(targets, contains('W1 @120,210 "Hello"'));
      expect(targets, contains('W2 @530,615 "World"'));
      expect(targets, isNot(contains('weak'))); // below confidence floor
      final resolved = await host.resolveTarget('W2');
      expect((resolved.x, resolved.y, resolved.text), (530.0, 615.0, 'World'));
    });
  });

  test('snapshot without tesseract still returns an image', () async {
    final runner = FakeRunner(
      binaries: {'import', 'convert', 'xdotool', 'xdg-open'},
      stdout: {'xdotool': '1920 1080\n'},
    );
    final host = LinuxX11HostControl(
      run: runner.call,
      env: (k) => k == 'DISPLAY' ? ':0' : null,
      hasBinary: runner.has,
      readBytes: (_) async => Uint8List.fromList([1, 2, 3]),
      makeTempDir: () async => Directory.systemTemp.createTemp('bluey-test-'),
    );
    final snap = await host.snapshot();
    expect(snap.jpeg, [1, 2, 3]);
    expect(snap.targets, isEmpty);
    expect((snap.width, snap.height), (1920.0, 1080.0));
  });
}
