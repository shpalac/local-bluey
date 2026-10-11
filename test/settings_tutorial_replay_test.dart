import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_bluey/services/tutorial.dart';
import 'package:local_bluey/ui/settings_screen.dart';

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

Future<void> _open(WidgetTester tester, TutorialController c) async {
  await tester.pumpWidget(MaterialApp(home: SettingsScreen(tutorial: c)));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.scrollUntilVisible(
    find.text('Replay first-steps tutorial'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
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
}
