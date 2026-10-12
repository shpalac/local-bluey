import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layout regression coverage; actual platform permission UI stays manual.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Strings.uiLanguage = UiLanguage.english;
  });

  testWidgets('settings usable across phone, tablet and desktop sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final size in <Size>[
      const Size(320, 720),
      const Size(800, 1100),
      const Size(1280, 850),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('AI brain'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('settings use a scrollable provider picker at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate((widget) => widget is SegmentedButton<BrainBackend>),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hebrew RTL and 200 percent text fit a compact screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Strings.uiLanguage = UiLanguage.hebrew;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: const SettingsScreen(),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.text('הגדרות'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
