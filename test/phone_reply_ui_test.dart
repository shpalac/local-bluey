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
    'reply-cleanup-pending': PhoneReplyReceiver.cleanupNote,
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
}
