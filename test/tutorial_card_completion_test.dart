import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Locked transitive platform seam verifies actual false persistence, not a fake controller.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:local_bluey/services/tutorial.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/ui/tutorial_card.dart';

class Store implements TutorialDoneStore {
  int writes = 0, clears = 0;
  bool done = false, fail = false;
  Completer<void>? entered, release;
  @override
  Future<void> markDone() async {
    writes++;
    entered?.complete();
    if (release != null) await release!.future;
    if (fail) throw StateError('private path and token');
    done = true;
  }

  @override
  Future<void> clear() async {
    clears++;
    done = false;
  }
}

class FalsePrefs extends InMemorySharedPreferencesStore {
  FalsePrefs() : super.empty();
  int writes = 0;
  bool fail = true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes++;
    if (fail) return false;
    return super.setValue(valueType, key, value);
  }
}

Future<void> mount(WidgetTester t, TutorialController c) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(body: TutorialCard(controller: c)),
  ),
);
void main() {
  testWidgets(
    'held skip joins repeated activation without early hide, then success',
    (t) async {
      final s = Store()
        ..entered = Completer<void>()
        ..release = Completer<void>();
      final c = TutorialController(store: s);
      addTearDown(c.dispose);
      await mount(t, c);
      final button = t.widget<TextButton>(
        find.byKey(const ValueKey('tutorial-complete')),
      );
      button.onPressed!();
      button.onPressed!();
      await t.pump();
      expect(s.writes, 1);
      expect(c.visible, isTrue);
      expect(s.done, isFalse);
      expect(find.text('Saving...'), findsOneWidget);
      expect(
        t
            .widget<TextButton>(find.byKey(const ValueKey('tutorial-complete')))
            .onPressed,
        isNull,
      );
      s.release!.complete();
      await c.completion;
      await t.pump();
      expect(c.visible, isFalse);
      expect(s.done, isTrue);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'thrown skip safe visible error and held explicit retry, no auto retry',
    (t) async {
      final s = Store()..fail = true;
      final c = TutorialController(store: s);
      addTearDown(c.dispose);
      await mount(t, c);
      await t.tap(find.text('Skip tutorial'));
      await t.pumpAndSettle();
      expect(
        find.text('Could not save tutorial completion. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private'), findsNothing);
      expect(c.visible, isTrue);
      expect(s.writes, 1);
      expect(t.takeException(), isNull);
      await t.pump();
      expect(s.writes, 1);
      s.fail = false;
      s.entered = Completer<void>();
      s.release = Completer<void>();
      await t.tap(find.text('Retry'));
      await t.pump();
      expect(s.writes, 2);
      expect(find.text('Saving...'), findsOneWidget);
      expect(
        find.text('Could not save tutorial completion. Try again.'),
        findsOneWidget,
      );
      s.release!.complete();
      await c.completion;
      await t.pump();
      expect(c.visible, isFalse);
      expect(s.clears, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'real false preference return reaches safe card failure and retry',
    (t) async {
      final old = SharedPreferencesStorePlatform.instance;
      final p = FalsePrefs();
      SharedPreferencesStorePlatform.instance = p;
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = p;
      final prefs = await SharedPreferences.getInstance();
      final c = TutorialController(prefsOverride: prefs);
      addTearDown(() {
        c.dispose();
        SharedPreferencesStorePlatform.instance = old;
        SharedPreferences.setMockInitialValues({});
      });
      await mount(t, c);
      await t.tap(find.text('Skip tutorial'));
      await t.pumpAndSettle();
      expect(c.visible, isTrue);
      expect(p.writes, 1);
      expect(find.text('Retry'), findsOneWidget);
      expect(t.takeException(), isNull);
      p.fail = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(p.writes, 2);
      expect(c.visible, isFalse);
    },
  );
  for (final point in [false, true]) {
    testWidgets(
      'natural ${point ? 'point' : 'answer'} failure displayed and explicitly recovered',
      (t) async {
        final s = Store()..fail = true;
        final c = TutorialController(store: s)..configure(pointing: point);
        addTearDown(c.dispose);
        await mount(t, c);
        c.notifyAwake();
        c.notifyAnswer();
        if (point) c.notifyPointed();
        await t.pumpAndSettle();
        expect(find.text('Retry'), findsOneWidget);
        expect(s.writes, 1);
        expect(t.takeException(), isNull);
        s.fail = false;
        await t.tap(find.text('Retry'));
        await t.pumpAndSettle();
        expect(c.visible, isFalse);
        expect(s.writes, 2);
        expect(s.clears, 0);
      },
    );
  }
  for (final fail in [false, true]) {
    testWidgets(
      'disposed card settles entered ${fail ? 'failure' : 'success'} without UI/reset',
      (t) async {
        final s = Store()
          ..fail = fail
          ..entered = Completer<void>()
          ..release = Completer<void>();
        final c = TutorialController(store: s);
        addTearDown(c.dispose);
        await mount(t, c);
        await t.tap(find.text('Skip tutorial'));
        await t.pump();
        final pending = c.completion!;
        final checked = pending.catchError((Object _) {});
        await t.pumpWidget(const SizedBox.shrink());
        s.release!.complete();
        await checked;
        await t.pump();
        expect(s.writes, 1);
        expect(s.clears, 0);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'owner replacement fences old completion, current card remains operable',
    (t) async {
      final s = Store()
        ..entered = Completer<void>()
        ..release = Completer<void>();
      final old = TutorialController(store: s),
          current = TutorialController(store: Store());
      addTearDown(() {
        old.dispose();
        current.dispose();
      });
      await mount(t, old);
      await t.tap(find.text('Skip tutorial'));
      await t.pump();
      final pending = old.completion!;
      await mount(t, current);
      s.release!.complete();
      await pending;
      await t.pump();
      expect(current.visible, isTrue);
      expect(find.text('Skip tutorial'), findsOneWidget);
      await t.tap(find.text('Skip tutorial'));
      await t.pumpAndSettle();
      expect(current.visible, isFalse);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('reentrant notification removes card during completion safely', (
    t,
  ) async {
    final s = Store();
    final c = TutorialController(store: s);
    addTearDown(c.dispose);
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    c.addListener(() => show.value = false);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, v, _) =>
                v ? TutorialCard(controller: c) : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await t.tap(find.text('Skip tutorial'));
    await t.pumpAndSettle();
    expect(s.writes, 1);
    expect(t.takeException(), isNull);
  });
  for (final width in [320.0, 1000.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final he in [false, true]) {
        testWidgets('actual completion pixels $width $scale $he', (t) async {
          t.view.physicalSize = Size(width, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final oldLanguage = Strings.uiLanguage;
          Strings.uiLanguage = he ? UiLanguage.hebrew : UiLanguage.english;
          addTearDown(() => Strings.uiLanguage = oldLanguage);
          final s = Store()..fail = true;
          final c = TutorialController(store: s);
          addTearDown(c.dispose);
          final pixels = Platform.environment['TUTORIAL_PIXELS'] == '1';
          var theme = ThemeData();
          if (pixels) {
            final latin = FontLoader('BlueyRoboto')
              ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
            await latin.load();
            final hebrew = FontLoader('BlueyHebrew')
              ..addFont(
                Future.value(
                  ByteData.sublistView(
                    File(
                      '/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf',
                    ).readAsBytesSync(),
                  ),
                ),
              );
            await hebrew.load();
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
              textTheme: theme.textTheme.apply(
                fontFamily: 'BlueyRoboto',
                fontFamilyFallback: ['BlueyHebrew'],
              ),
            );
          }
          final key = GlobalKey();
          await t.pumpWidget(
            MaterialApp(
              theme: theme,
              home: RepaintBoundary(
                key: key,
                child: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 900),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: Directionality(
                      textDirection: he ? TextDirection.rtl : TextDirection.ltr,
                      child: SingleChildScrollView(
                        child: TutorialCard(controller: c),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final label = '${width.toInt()}-${scale.toInt()}-${he ? 'he' : 'en'}';
          Future<void> shot(String state) async {
            await t.pump();
            expect(t.takeException(), isNull);
            final button = t.getRect(
              find.byKey(const ValueKey('tutorial-complete')),
            );
            expect(button.width, greaterThanOrEqualTo(48));
            expect(button.height, greaterThanOrEqualTo(48));
            if (!pixels) return;
            await t.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('docs/evidence/issue466')
                ..createSync(recursive: true);
              await File('${dir.path}/$label-$state.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          await t.tap(find.text('Skip tutorial'));
          await t.pumpAndSettle();
          await shot('error');
          s.fail = false;
          s.entered = Completer<void>();
          s.release = Completer<void>();
          await t.tap(find.text(he ? 'נסה שוב' : 'Retry'));
          await t.pump();
          await shot('retry');
          s.release!.complete();
          await c.completion;
          await t.pumpAndSettle();
          expect(c.visible, isFalse);
          await c.reset();
          s.entered = Completer<void>();
          s.release = Completer<void>();
          await t.pump();
          await t.tap(find.text('Skip tutorial'));
          await t.pump();
          await shot('pending');
          s.release!.complete();
          await c.completion;
          await t.pumpAndSettle();
        });
      }
    }
  }
}
