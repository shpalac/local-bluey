import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('#87: semantic colors pass WCAG AA in both themes', () {
    expect(AppTokens.contrastPassesAA(), isTrue);
    expect(
      AppTokens.contrastRatio(AppTokens.darkOnSurface, AppTokens.darkSurface),
      greaterThanOrEqualTo(AppTokens.wcagAA),
    );
    expect(
      AppTokens.contrastRatio(AppTokens.lightOnSurface, AppTokens.lightSurface),
      greaterThanOrEqualTo(AppTokens.wcagAA),
    );
  });

  test('#87: override persists and defaults to system', () async {
    await ThemeController.instance.load();
    expect(ThemeController.instance.mode, ThemeMode.system);
    await ThemeController.instance.setMode(ThemeMode.light);
    SharedPreferences.setMockInitialValues({'theme.mode': 'dark'});
    await ThemeController.instance.load();
    expect(ThemeController.instance.mode, ThemeMode.dark);
    await ThemeController.instance.setMode(ThemeMode.system);
  });

  testWidgets('#87: app builds in both themes', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Text('hello')),
        ),
      );
      expect(find.text('hello'), findsOneWidget);
    }
  });
}
