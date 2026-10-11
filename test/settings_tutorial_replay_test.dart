import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/tutorial.dart';
import 'package:local_bluey/ui/settings_screen.dart';

class _Reentrant extends TutorialController {
  _Reentrant({required super.store});
  VoidCallback? onReset;
  @override
  Future<void> reset() {
    onReset?.call();
    return super.reset();
  }
}

class _Store implements TutorialDoneStore {
  int removes = 0;
  Completer<void>? entered;
  Completer<void>? hold;
  Object? failure;

  @override
  Future<void> markDone() async {}

  @override
  Future<void> clear() async {
    removes++;
    entered?.complete();
    await hold?.future;
    if (failure != null) throw failure!;
  }
}

Future<void> _open(
  WidgetTester tester,
  TutorialController c, [
  String label = 'Replay first-steps tutorial',
]) async {
  await tester.pumpWidget(MaterialApp(home: SettingsScreen(tutorial: c)));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.scrollUntilVisible(
    find.text(label),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text(label));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('success is announced only after reset settles; taps join', (
    tester,
  ) async {
    final store = _Store()
      ..entered = Completer<void>()
      ..hold = Completer<void>();
    final c = TutorialController(store: store);
    addTearDown(c.dispose);
    await _open(tester, c);
    await tester.tap(find.text('Replay first-steps tutorial'));
    await tester.pump();
    await tester.tap(find.text('Resetting...'));
    await tester.pump();
    expect(store.removes, 1);
    expect(find.text('Tutorial will show on the main screen.'), findsNothing);
    store.hold!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Tutorial will show on the main screen.'), findsOneWidget);
  });

  testWidgets('failure is safe, then explicit retry succeeds', (tester) async {
    final store = _Store()..failure = StateError('/private/path secret');
    final c = TutorialController(store: store);
    addTearDown(c.dispose);
    await _open(tester, c);
    await tester.tap(find.text('Replay first-steps tutorial'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Could not reset the tutorial. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private'), findsNothing);
    expect(find.text('Tutorial will show on the main screen.'), findsNothing);
    store.failure = null;
    await tester.tap(find.text('Could not reset the tutorial. Tap to retry.'));
    await tester.pump();
    await tester.pump();
    expect(store.removes, 2);
    expect(find.text('Tutorial will show on the main screen.'), findsOneWidget);
  });

  testWidgets('disposed route shows nothing after held reset', (tester) async {
    final store = _Store()
      ..entered = Completer<void>()
      ..hold = Completer<void>();
    final c = TutorialController(store: store);
    addTearDown(c.dispose);
    await _open(tester, c);
    await tester.tap(find.text('Replay first-steps tutorial'));
    await tester.pump();
    await store.entered!.future;
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    store.hold!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reentrant tap during reset joins the installed attempt', (
    tester,
  ) async {
    final store = _Store()
      ..entered = Completer<void>()
      ..hold = Completer<void>();
    final c = _Reentrant(store: store);
    addTearDown(c.dispose);
    await _open(tester, c);
    final tile = find.widgetWithText(ListTile, 'Replay first-steps tutorial');
    c.onReset = () {
      c.onReset = null;
      tester.widget<ListTile>(tile).onTap!();
    };
    await tester.tap(tile);
    await tester.pump();
    expect(store.removes, 1);
    store.hold!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Tutorial will show on the main screen.'), findsOneWidget);
  });

  testWidgets('replaced owner result is dropped; new owner can replay', (
    tester,
  ) async {
    final old = _Store()
      ..entered = Completer<void>()
      ..hold = Completer<void>();
    final fresh = _Store();
    final c1 = TutorialController(store: old);
    final c2 = TutorialController(store: fresh);
    addTearDown(c1.dispose);
    addTearDown(c2.dispose);
    await _open(tester, c1);
    await tester.tap(find.text('Replay first-steps tutorial'));
    await tester.pump();
    await old.entered!.future;
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(tutorial: c2)));
    old.hold!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Replay first-steps tutorial'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Replay first-steps tutorial'));
    await tester.pump();
    await tester.pump();
    expect(fresh.removes, 1);
    expect(find.text('Tutorial will show on the main screen.'), findsOneWidget);
  });

  testWidgets('Hebrew pending and failure text is localized', (tester) async {
    final store = _Store()
      ..entered = Completer<void>()
      ..hold = Completer<void>()
      ..failure = StateError('x');
    final c = TutorialController(store: store);
    addTearDown(c.dispose);
    Strings.uiLanguage = UiLanguage.hebrew;
    addTearDown(() => Strings.uiLanguage = UiLanguage.english);
    await _open(tester, c, 'הפעלה חוזרת של המדריך');
    await tester.tap(find.text('הפעלה חוזרת של המדריך'));
    await tester.pump();
    expect(find.text('מאפס...'), findsOneWidget);
    store.hold!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('לא ניתן לאפס את המדריך. נסו שוב.'), findsOneWidget);
    expect(
      find.text('לא ניתן לאפס את המדריך. הקישו כדי לנסות שוב.'),
      findsOneWidget,
    );
  });
}
