import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/llm/llm_provider.dart';
import 'package:local_bluey/services/first_success.dart';
import 'package:local_bluey/services/onboarding_checks.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/services/support_matrix.dart';
import 'package:local_bluey/ui/face_screen.dart';
import 'package:local_bluey/ui/onboarding_screen.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:local_bluey/ui/theme.dart';
import 'package:local_bluey/ui/unsupported_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screenshot harness (#180): renders each screen in a fixed state with
/// fake data (no network, no keys) and compares against golden files.
/// Regenerate all images with one command:
///   tool/regenerate_screenshots.sh
/// Determinism: pinned surface size + DPR, bundled Roboto (loaded below),
/// fixed light/dark theme, English UI, no clocks or animations driven by
/// wall time. Run twice -> identical files.
Future<(ServiceReadiness, ServiceReadiness)> _fakeReady() async =>
    (ServiceReadiness.ready, ServiceReadiness.ready);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Real glyphs instead of the Ahem test font: the bundled Roboto is
    // registered under its own family name in pubspec.yaml.
    final loader = FontLoader('BlueyRoboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await loader.load();
    // Hebrew glyphs for the RTL shots (Roboto has none): Noto Sans Hebrew
    // (SIL OFL) is committed next to the harness so every machine renders
    // the same pixels.
    final hebrew = FontLoader('NotoSansHebrew')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('test/screenshots/fonts/NotoSansHebrew-Regular.ttf')
                .readAsBytesSync(),
          ),
        ),
      );
    await hebrew.load();
    // Icon glyphs: the Material icon font from the pinned Flutter SDK, so
    // icons are not blank squares.
    final root = Platform.environment['FLUTTER_ROOT'];
    final icons = root == null
        ? null
        : File(
            '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          );
    if (icons == null || !icons.existsSync()) {
      throw StateError('Material icon font not found under FLUTTER_ROOT');
    }
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await iconLoader.load();
  });

  ThemeData withFonts(ThemeData base) => base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'BlueyRoboto',
      fontFamilyFallback: const ['NotoSansHebrew'],
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Strings.uiLanguage = UiLanguage.english;
  });

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget child, {
    bool dark = false,
    Size? size,
    double textScale = 1.0,
    bool rtl = false,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: withFonts(dark ? AppTheme.dark() : AppTheme.light()),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: app!,
          ),
        ),
        // The app hosts the face in a Scaffold (lib/main.dart); mirror it so
        // text gets Material's default style instead of a debug fallback.
        home: child is FaceScreen ? Scaffold(body: child) : child,
      ),
    );
    // Fixed pumps instead of pumpAndSettle: the settings overlay has
    // perpetual diagnostics animations that never fully settle.
    await tester.pump();
    // Let real async work (SharedPreferences, readiness probes) finish so a
    // loading spinner is never captured as the documentation image.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name'),
    );
  }

  testWidgets('face listening', (tester) async {
    await shot(
      tester,
      'face-listening-light.png',
      FaceScreen(face: FaceState(), awake: true),
    );
  });

  testWidgets('face thinking', (tester) async {
    await shot(
      tester,
      'face-thinking-light.png',
      FaceScreen(
        face: FaceState(mood: Mood.thinking),
        awake: true,
        status: BlueyStatus.thinking,
      ),
    );
  });

  testWidgets('face answer bubble short', (tester) async {
    await shot(
      tester,
      'face-answer-short-light.png',
      FaceScreen(
        face: FaceState(mood: Mood.talking, talk: 0.6),
        awake: true,
        bubble: 'On it.',
      ),
    );
  });

  testWidgets('face answer bubble long', (tester) async {
    await shot(
      tester,
      'face-answer-long-light.png',
      FaceScreen(
        face: FaceState(mood: Mood.talking, talk: 0.4),
        awake: true,
        bubble:
            'The renewal is \$48,250, due July 15. The April quote was '
            'draft-only, so the May thread is the one that counts.',
      ),
    );
  });

  testWidgets('face sleepy', (tester) async {
    await shot(
      tester,
      'face-sleepy-light.png',
      FaceScreen(face: FaceState(mood: Mood.sleepy)),
    );
  });

  testWidgets('face error', (tester) async {
    await shot(
      tester,
      'face-error-light.png',
      FaceScreen(
        face: FaceState(),
        awake: true,
        status: BlueyStatus.error,
        bubble: 'Lost the brain endpoint. Check Settings.',
      ),
    );
  });

  testWidgets('face dark theme', (tester) async {
    await shot(
      tester,
      'face-listening-dark.png',
      FaceScreen(face: FaceState(), awake: true),
      dark: true,
    );
  });

  testWidgets('onboarding first step', (tester) async {
    await shot(
      tester,
      'onboarding-start-light.png',
      OnboardingScreen(
        readiness: _fakeReady,
        onDone: () {},
        checker: const _AllDeniedChecker(),
      ),
    );
  });

  // Onboarding at the sizes and text scales #223 asks for. A render
  // overflow fails the test, so these also guard against clipped controls.
  for (final v in const [
    ('compact-light', Size(720, 520), false, 1.0),
    ('compact-dark-200', Size(720, 520), true, 2.0),
    ('desktop-light', Size(1360, 845), false, 1.0),
    ('desktop-dark', Size(1360, 845), true, 1.0),
    ('desktop-light-200', Size(1360, 845), false, 2.0),
    ('wide-light', Size(1920, 1080), false, 1.0),
  ]) {
    testWidgets('onboarding ${v.$1}', (tester) async {
      await shot(
        tester,
        'onboarding-${v.$1}.png',
        OnboardingScreen(
          readiness: _fakeReady,
          onDone: () {},
          checker: const _AllDeniedChecker(),
        ),
        size: v.$2,
        dark: v.$3,
        textScale: v.$4,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // Hebrew / RTL onboarding (#227): first step, 200% text, dark.
  for (final v in const [
    ('he-light', Size(1360, 845), false, 1.0),
    ('he-dark-200', Size(720, 520), true, 2.0),
  ]) {
    testWidgets('onboarding ${v.$1}', (tester) async {
      Strings.uiLanguage = UiLanguage.hebrew;
      addTearDown(() => Strings.uiLanguage = UiLanguage.english);
      await shot(
        tester,
        'onboarding-${v.$1}.png',
        OnboardingScreen(
          readiness: _fakeReady,
          onDone: () {},
          checker: const _AllDeniedChecker(),
        ),
        size: v.$2,
        dark: v.$3,
        textScale: v.$4,
        rtl: true,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings default', (tester) async {
    await shot(tester, 'settings-default-light.png', const SettingsScreen());
  });

  testWidgets('settings dark', (tester) async {
    await shot(
      tester,
      'settings-default-dark.png',
      const SettingsScreen(),
      dark: true,
    );
  });

  testWidgets('unsupported platform', (tester) async {
    await shot(
      tester,
      'unsupported-linux-light.png',
      SizedBox(
        width: 800,
        height: 700,
        child: UnsupportedScreen(
          profile: SupportMatrix.profile(operatingSystem: 'linux'),
        ),
      ),
    );
  });
}

class _AllDeniedChecker implements PermissionChecker {
  const _AllDeniedChecker();

  @override
  Future<bool> accessibility() async => false;
  @override
  Future<bool> screenRecording() async => false;
  @override
  Future<bool> microphone() async => false;
  @override
  Future<bool> localNetwork() async => false;
}
