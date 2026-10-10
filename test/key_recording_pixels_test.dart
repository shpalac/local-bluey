import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/ui/face_screen.dart';
import 'package:local_bluey/services/audio_capture.dart';
import 'package:local_bluey/services/key_recording_intent.dart';

class Driver implements RecorderDriver {
  bool fail = true;
  bool startFail = false;
  Completer<void>? entered, release;
  @override
  Future<bool> hasPermission() async {
    if (entered != null) {
      entered!.complete();
      await release!.future;
    }
    if (fail) throw StateError('private permission');
    return true;
  }

  @override
  Future<void> start(String p) async {
    if (startFail) throw StateError('private start');
  }

  @override
  Future<String?> stop() async => null;
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual face with synthetic owner current failure pending and recovery',
    (t) async {
      final driver = Driver(),
          dir = Directory.systemTemp.createTempSync('key-pixels');
      final capture = AudioCapture(
        driver: driver,
        tempDirProvider: () async => dir,
      );
      final owner = KeyRecordingIntent(capture: capture, deliver: (_) async {});
      addTearDown(() async {
        try {
          await owner.disposeIntent();
        } catch (_) {}
        owner.dispose();
        await capture.dispose();
        dir.deleteSync(recursive: true);
      });
      t.view.physicalSize = const Size(1000, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var theme = ThemeData();
      if (Platform.environment['KEY_PIXELS'] == '1') {
        final font = FontLoader('BlueyRoboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
        await font.load();
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'BlueyRoboto'),
        );
      }
      final boundary = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: ListenableBuilder(
                listenable: owner,
                builder: (context, _) => FaceScreen(
                  face: FaceState(),
                  awake: true,
                  bubble: switch (owner.status) {
                    KeyRecordingStatus.failed =>
                      'Could not finish key recording. Try again.',
                    KeyRecordingStatus.uncertain =>
                      'Key recording cleanup could not be verified.',
                    KeyRecordingStatus.pending => 'Waiting for microphone…',
                    KeyRecordingStatus.listening => 'Listening…',
                    _ => null,
                  },
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> shot(String n) async {
        if (Platform.environment['KEY_PIXELS'] != '1') return;
        await t.pump(const Duration(milliseconds: 500));
        await t.runAsync(() async {
          final im =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/391-$n.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          im.dispose();
        });
      }

      await t.runAsync(() async {
        await expectLater(owner.start(), throwsA(isA<KeyRecordingException>()));
      });
      await t.pump();
      expect(
        find.text('Could not finish key recording. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private'), findsNothing);
      await shot('failure');
      driver.fail = false;
      driver.entered = Completer<void>();
      driver.release = Completer<void>();
      late Future<void> work;
      await t.runAsync(() async {
        work = owner.start();
      });
      await t.pump();
      expect(driver.entered!.isCompleted, true);
      expect(find.text('Waiting for microphone…'), findsOneWidget);
      await shot('pending');
      driver.release!.complete();
      driver.entered = null;
      await t.runAsync(() async {
        await work;
      });
      await t.pump();
      expect(find.text('Listening…'), findsOneWidget);
      await shot('recovery');
      await t.runAsync(() async {
        await owner.cancel();
      });
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Listening…'), findsNothing);
      await shot('cancel');
      driver.startFail = true;
      await t.runAsync(() async {
        await expectLater(owner.start(), throwsA(isA<KeyRecordingException>()));
      });
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Key recording cleanup could not be verified.'),
        findsOneWidget,
      );
      await shot('uncertain');
      await t.pumpWidget(const SizedBox.shrink());
      expect(t.takeException(), isNull);
    },
  );
}
