import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/hold_key_caller.dart';
import 'package:local_bluey/ui/hold_key_caller_notice.dart';
import 'package:local_bluey/ui/face_screen.dart';
import 'package:local_bluey/link/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual shared notice failure, entered retry and recovery render safely',
    (tester) async {
      var fail = true, calls = 0;
      Completer<void>? entered, release;
      final c = HoldKeyCaller.operations(
        load: () async {},
        close: () async {},
        sync: () async {
          calls++;
          if (entered != null) {
            entered.complete();
            await release!.future;
          }
          if (fail) throw StateError('private endpoint and secret');
        },
      );
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1000, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var theme = ThemeData();
      if (Platform.environment['HOLD_CALLER_PIXELS'] == '1') {
        final loader = FontLoader('BlueyRoboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                ).readAsBytesSync(),
              ),
            ),
          );
        await icons.load();
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'BlueyRoboto'),
        );
      }
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: FaceScreen(
                face: FaceState(),
                awake: false,
                bubble: 'Synthetic host',
              ),
              bottomNavigationBar: HoldKeyCallerNotice(caller: c),
            ),
          ),
        ),
      );
      await c.loadAndSync();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not update hold-key settings. Shortcut state is not verified.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private'), findsNothing);
      Future<void> shot(String name) async {
        if (Platform.environment['HOLD_CALLER_PIXELS'] != '1') return;
        await tester.pump();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/395-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await shot('failure');
      entered = Completer<void>();
      release = Completer<void>();
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(entered.isCompleted, true);
      expect(find.text('Retrying...'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Retrying...'))
            .onPressed,
        isNull,
      );
      await shot('retry');
      release.complete();
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(MaterialBanner), findsNothing);
      await shot('recovery');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
