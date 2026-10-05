import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/line_connection.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/link/phone_server.dart';
import 'package:local_bluey/services/linux_x11_host_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// E2E over real loopback TCP (#154): a raw phone client pairs with the
/// PhoneServer (the production link protocol), then issues X11 control
/// calls through the Linux host backend - the same two halves that meet
/// on a real LAN: Android emulator phone <-> Linux host under Xvfb in CI.
Future<(LineConnection, Socket)> _client(int port) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  return (LineConnection(socket)..start(), socket);
}

Future<void> _until(
  bool Function() condition, [
  Duration timeout = const Duration(seconds: 5),
]) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('phone <-> linux host e2e (#154)', () {
    test(
      'paired phone sends hold-to-talk, host backend warps the pointer',
      () async {
        final server = PhoneServer();
        addTearDown(server.stop);
        server.onPairRequest = (_) async => true;
        await server.start(advertise: false);

        final (phone, _) = await _client(server.port);
        addTearDown(phone.close);
        final received = <Packet>[];
        phone.packets.listen(received.add);
        phone.send(Packet(hello: 'EmulatorPhone'));

        // Pairing completes over the wire (key handoff included).
        await _until(() => received.any((p) => p.command == 'paired'));
        expect(server.phoneNames, contains('EmulatorPhone'));

        // The phone issues hold-to-talk over the link, as in production.
        final requests = <Packet>[];
        final sub = server.requests.listen(requests.add);
        addTearDown(sub.cancel);
        phone.send(Packet(command: 'holdStart', text: 'what is this?'));
        phone.send(Packet(command: 'holdEnd'));

        await _until(
          () =>
              requests.any((p) => p.command == 'holdStart') &&
              requests.any((p) => p.command == 'holdEnd'),
        );

        // The host side answers with a real control call through the X11
        // backend - the warp must reach xdotool as a mousemove.
        final calls = <(String, List<String>)>[];
        final realDisplay = Platform.environment['DISPLAY'];
        Future<ProcessResult> fakeRun(String exe, List<String> args) async {
          calls.add((exe, args));
          return ProcessResult(0, 0, '', '');
        }

        final host = LinuxX11HostControl(
          // Under Xvfb (CI lane, #154) use the real process runner so the
          // warp actually moves the pointer on the X server; otherwise a
          // fake runner just records the command.
          run: realDisplay == null ? fakeRun : null,
          env: (k) => k == 'DISPLAY' ? (realDisplay ?? ':99') : null,
          hasBinary: (_) async => true,
        );
        if (realDisplay == null) {
          await host.warp(640, 360);
          expect(calls.last.$1, 'xdotool');
          expect(calls.last.$2, ['mousemove', '640', '360']);
        } else {
          // Real X server: verify the warp actually moved the pointer.
          // xdotool getmouselocation reads a cached position on fresh
          // connections under Xvfb, so watch MotionNotify on a held-open
          // `xev -root` connection instead: the warp must appear there.
          // stdbuf -oL: xev block-buffers its stdout when piped, so force
          // line buffering or the MotionNotify lines never reach us.
          final xev = await Process.start(
            'stdbuf',
            ['-oL', 'xev', '-root', '-event', 'mouse'],
            environment: {'DISPLAY': realDisplay},
          );
          addTearDown(() => xev.kill());
          final xevOut = StringBuffer();
          xev.stdout.transform(SystemEncoding().decoder).listen(xevOut.write);
          // xev needs a beat to connect and select for events; there is no
          // startup banner to wait on. Re-issue the warp each poll - an
          // idempotent mousemove - until the held-open connection sees it.
          var seen = '';
          for (var i = 0; i < 15; i++) {
            await host.warp(640, 360);
            await Future<void>.delayed(const Duration(milliseconds: 200));
            seen = xevOut.toString();
            if (seen.contains('root:(640,360)')) break;
          }
          expect(seen, contains('root:(640,360)'));
        }

        // An unpaired phone cannot drive the host: non-allowlisted commands
        // are dropped before they ever reach requests.
        final (stranger, _) = await _client(server.port);
        addTearDown(stranger.close);
        stranger.packets.listen((_) {});
        stranger.send(Packet(hello: 'Stranger'));
        stranger.send(Packet(command: 'holdStart'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          requests.where((p) => p.command == 'holdStart').length,
          1, // only the paired phone's
        );
      },
    );
  });
}
