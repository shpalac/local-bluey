import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/ui/routine_review_card.dart';

const draft = Routine(
  name: 'טיוטת דוגמה',
  trigger: 'sample שלום',
  instructions: 'הוראות בדיקה בלבד. Open the sample editor.',
  enabled: false,
);
void main() {
  for (final rtl in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('review 320 RTL=$rtl scale=$scale pending/failure/retry', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final old = Strings.uiLanguage;
        Strings.uiLanguage = rtl ? UiLanguage.hebrew : UiLanguage.english;
        addTearDown(() => Strings.uiLanguage = old);
        final capture = Platform.environment['REVIEW_PIXELS'];
        if (capture != null) {
          final font = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
              .readAsBytesSync();
          await (FontLoader(
            'ReviewCapture',
          )..addFont(Future.value(ByteData.sublistView(font)))).load();
        }
        var calls = 0, declines = 0;
        final gate = Completer<void>();
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: capture == null ? null : 'ReviewCapture',
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: child!,
                ),
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: RoutineReviewCard(
                    routine: draft,
                    onAccept: (value) async {
                      expect(identical(value, draft), isTrue);
                      expect(value.enabled, isFalse);
                      calls++;
                      if (calls == 1) await gate.future;
                    },
                    onDecline: () => declines++,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text(draft.instructions), findsOneWidget);
        await tester.ensureVisible(find.byType(FilledButton));
        await tester.pump();
        if (capture != null) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('$capture/${rtl ? 'he' : 'en'}-$scale.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        expect(calls, 1);
        expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed,
          isNull,
        );
        gate.completeError(StateError('fabricated-private-detail'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            rtl
                ? 'בדיקת הטיוטה נכשלה. נסו שוב.'
                : 'Draft review failed. Try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('fabricated-private'), findsNothing);
        await tester.ensureVisible(find.byType(FilledButton));
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(calls, 2);
        await tester.ensureVisible(find.byType(TextButton));
        await tester.tap(find.byType(TextButton));
        expect(declines, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'keyboard Enter chooses disabled review and semantic tap is exposed',
    (tester) async {
      var calls = 0;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoutineReviewCard(
              routine: draft,
              onAccept: (_) async => calls++,
              onDecline: () {},
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(FilledButton)),
        matchesSemantics(
          label: 'Accept disabled draft',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
      semantics.dispose();
    },
  );
  testWidgets('enabled legacy Routine cannot invoke accept', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutineReviewCard(
            routine: const Routine(
              name: 'sample',
              trigger: 'sample',
              instructions: 'sample',
            ),
            onAccept: (_) async => calls++,
            onDecline: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(FilledButton));
    expect(calls, 0);
  });
}
