import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/services/phone_reply.dart';
import 'package:local_bluey/ui/face_screen.dart';

// Opt-in pixel capture of the phone reply bubble (#372). Synthetic render on
// the test engine only, no device claim:
//   flutter test test/phone_reply_ui_test.dart \
//     --dart-define=REPLY_CAPTURE_DIR=build/reply-captures
void main() {
  const captureDir = String.fromEnvironment('REPLY_CAPTURE_DIR');
  final cases = {
    'reply-error-note':
        'Here is your answer.\n(Could not play the reply audio.)',
    'reply-cleanup-pending': ReplyBubble.compose('Here is your answer.', true),
  };
  for (final entry in cases.entries) {
    testWidgets('bubble shows ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (captureDir.isNotEmpty) {
        await tester.runAsync(() async {
          final data = await File(
            const String.fromEnvironment(
              'LOCK_CAPTURE_FONT',
              defaultValue: '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
            ),
          ).readAsBytes();
          await (FontLoader(
            'Roboto',
          )..addFont(Future.value(ByteData.sublistView(data)))).load();
        });
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            home: Scaffold(
              body: FaceScreen(
                face: FaceState(mood: Mood.happy),
                bubble: entry.value,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining(entry.value.split('\n').first),
        findsOneWidget,
      );
      if (captureDir.isEmpty) return;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await Directory(captureDir).create(recursive: true);
        await File('$captureDir/${entry.key}.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
    });
  }

  testWidgets(
    'cleanup note keeps the answer, clears on recovery, no late use',
    (tester) async {
      final sessions = <_FakeSession>[];
      late PhoneReplyReceiver receiver;
      final key = GlobalKey<_HarnessState>();
      final dir = Directory.systemTemp.createTempSync('reply_ui_');
      addTearDown(() => dir.deleteSync(recursive: true));
      receiver = PhoneReplyReceiver(
        createSession: () {
          final s = _FakeSession();
          sessions.add(s);
          return s;
        },
        send: (_) {},
        showText: (t) => key.currentState?.show(t),
        isActive: () => key.currentState?.mounted ?? false,
        tempDir: () async => dir,
      );
      await tester.pumpWidget(_Harness(receiver, key: key));
      await tester.runAsync(() async {
        receiver.handle(
          Packet(command: 'say', text: 'Hello', audio: 'BQUF', speech: 1),
        );
        await receiver.idle;
        sessions[0].failing = true;
        receiver.handle(Packet(command: 'stopSpeech'));
        await receiver.idle;
      });
      await tester.pump();
      expect(
        key.currentState!.bubble,
        'Hello\n(${PhoneReplyReceiver.cleanupNote})',
      );
      await tester.runAsync(() async {
        sessions[0].failing = false;
        receiver.handle(Packet(command: 'stopSpeech'));
        await receiver.idle;
      });
      await tester.pump();
      expect(key.currentState!.bubble, 'Hello');
      // Dispose while stuck, then a late completion: nothing throws.
      await tester.runAsync(() async {
        receiver.handle(
          Packet(command: 'say', text: 'Again', audio: 'BQUF', speech: 2),
        );
        await receiver.idle;
        sessions[1].failing = true;
        await tester.pumpWidget(const SizedBox());
        await receiver.dispose();
        sessions[1].controller.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      expect(tester.takeException(), isNull);
    },
  );
}

class _Harness extends StatefulWidget {
  const _Harness(this.receiver, {super.key});
  final PhoneReplyReceiver receiver;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String? bubble;
  String? replyText;
  bool pending = false;

  @override
  void initState() {
    super.initState();
    widget.receiver.cleanupPending.addListener(_onCleanup);
  }

  void _onCleanup() {
    if (!mounted) return;
    final now = widget.receiver.cleanupPending.value > 0;
    if (now == pending) return;
    setState(() {
      bubble = ReplyBubble.next(bubble, replyText, pending, now);
      pending = now;
    });
  }

  void show(String text) => setState(() {
    replyText = text;
    bubble = ReplyBubble.compose(text, pending);
  });

  @override
  void dispose() {
    widget.receiver.cleanupPending.removeListener(_onCleanup);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: FaceScreen(
        face: FaceState(mood: Mood.happy),
        bubble: bubble,
      ),
    ),
  );
}

class _FakeSession implements ReplySession {
  final controller = StreamController<void>.broadcast();
  bool failing = false;

  @override
  Stream<void> get completions => controller.stream;
  @override
  Future<void> play(String path) async {}
  @override
  Future<void> stop() async {
    if (failing) throw StateError('stop');
  }

  @override
  Future<void> dispose() async {
    if (failing) throw StateError('dispose');
  }
}
